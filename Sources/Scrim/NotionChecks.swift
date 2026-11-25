import AppKit
import SwiftUI
import ScrimCore

private struct NotionCheckError: Error, CustomStringConvertible { let description: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NotionCheckError(description: message) }
}
private func waitFor(_ description: String, seconds: TimeInterval = 15, until predicate: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() {
        guard Date() < deadline else { throw NotionCheckError(description: "Timed out: " + description) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}
/// Reads the fixture's synthetic state so checks see what actually reached the "server".
private func fixtureState(_ base: URL, _ key: String) throws -> [String: [String: Any]] {
    var result: [String: [String: Any]]?
    URLSession.shared.dataTask(with: base.appendingPathComponent("__state")) { data, _, _ in
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        result = json?[key] as? [String: [String: Any]] ?? [:]
    }.resume()
    try waitFor("fixture state") { result != nil }
    return result ?? [:]
}
private func fixturePages(_ base: URL) throws -> [String: [String: Any]] { try fixtureState(base, "pages") }
private func fixtureBlocks(_ base: URL) throws -> [String: [String: Any]] { try fixtureState(base, "blocks") }
/// With SCRIM_NOTION_SNAPSHOTS=<directory>, saves light and dark PNGs of a panel state for visual review.
@MainActor private func snapshot(_ model: NotionTasksModel, _ name: String, editing: Bool = false) throws {
    guard let directory = ProcessInfo.processInfo.environment["SCRIM_NOTION_SNAPSHOTS"] else { return }
    let size = CGSize(width: 420, height: 460)
    for dark in [false, true] {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let content = NotionTasksView(model: model, now: Date(), size: size, editing: editing)
            .tint(ScrimPalette.blue).frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size); host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance; window.contentView = host; window.isReleasedWhenClosed = false
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NotionCheckError(description: "snapshot") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("notion-\(name)-\(dark ? "dark" : "light").png"))
        window.contentView = nil
    }
}
private func resetFixture(_ base: URL) throws {
    var done = false
    URLSession.shared.dataTask(with: base.appendingPathComponent("__reset")) { _, _, _ in done = true }.resume()
    try waitFor("fixture reset") { done }
}

/// Drives the real panel model and settings controller against scripts/notion-fixture.py.
/// Uses an in-memory token; never reads the Keychain or contacts api.notion.com.
@MainActor func verifyNotionTasks(fixture: URL) throws {
    let previous = NotionEnvironment.current
    defer { NotionEnvironment.current = previous }
    NotionEnvironment.current = NotionEnvironment(tokens: MemoryNotionTokenStore("fixture-token"), baseURL: fixture)
    try resetFixture(fixture)

    // Setup: pick an existing status database and accept the guessed mapping.
    let model = NotionTasksModel(mapping: nil)
    var saved: NotionTaskMapping?
    model.onConfigurationChange = { saved = $0 }
    model.setActive(true)
    try check(model.tasks.isEmpty && !model.loading, "An unconfigured panel must not query Notion")
    try snapshot(model, "unconfigured")
    model.beginConfiguring()
    try waitFor("data source search") { model.searchResults.count == 2 && !model.searching }
    try check(model.searchResults.allSatisfy { $0.kind == .dataSource }, "Source search must list data sources only")
    try snapshot(model, "choose-source")
    model.chooseSource("ds-status")
    try waitFor("status mapping") { model.step == .mapColumns && model.draft != nil }
    try snapshot(model, "map-columns")
    try check(model.draft?.completion == .status(property: "%3AUPp", done: "o3") && model.draft?.dueProperty == "d%2Fe",
              "Status databases must map completion to the Complete group's first option and pick the date column")
    model.finishConfiguring()
    try check(saved == model.mapping && saved != nil && !model.isConfiguring, "Finishing setup must save the mapping to the panel")
    try check(WidgetSpec(url: WidgetSpec(kind: .notionTasks, notionTasks: saved).url)?.notionTasks == saved, "Mapping must survive the panel URL")
    try waitFor("status tasks") { model.lastLoaded != nil && !model.loading }
    try check(model.tasks.map(\.title) == ["見積もりを確認", "資料を共有", "週次レポート"],
              "Open tasks must exclude every Complete-group status and list due tasks first: \(model.tasks.map(\.title))")
    do {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let url = WidgetSpec(kind: .notionTasks, notionTasks: saved).url
        let record = PanelRecord(url: url, placement: FractionalFrame(frame: CGRect(x: 20, y: 20, width: 420, height: 320),
                                                                    screen: CGSize(width: 1200, height: 800)))
        store.panels = [record]
        let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
        controller.show(.pinned, immediately: true)
        defer { controller.show(.hidden, immediately: true) }
        let panel = try XCTUnwrapCheck(controller.views[record.id], "previously configured Notion task panel")
        let widget = try XCTUnwrapCheck(panel.subviews.compactMap { $0 as? NativeWidgetPanel }.first, "native task widget")
        try waitFor("restored Notion task panel") { widget.model.notion.tasks.count == 3 }
        try check(widget.model.notion.mapping == saved, "The saved panel must restore its Notion database mapping")
        controller.setEditing(true)
        let hint = try XCTUnwrapCheck(panel.subviews.compactMap { $0 as? PanelEditHint }.first, "task panel menu control")
        try check(hint.accessibilityPerformPress(), "The task panel menu must open from edit mode")
        let menu = try XCTUnwrapCheck(panel.currentMenu, "task panel menu")
        let setup = try XCTUnwrapCheck(menu.setupItems.first, "database configuration item")
        menu.choose(setup.tag)
        try check(widget.model.notion.isConfiguring && !panel.isShowingMenu, "The database menu item must open task setup")
    }

    // Add, complete with undo, complete for real, edit.
    model.add(title: "新しいタスク", due: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 27)))
    try waitFor("created task") { model.tasks.contains { $0.title == "新しいタスク" } }
    var pages = try fixturePages(fixture)
    try check(pages.values.contains { $0["title"] as? String == "新しいタスク" && $0["due"] as? String == "2026-11-27" },
              "Adding must create the page with its due date in Notion")
    try snapshot(model, "list")
    let estimate = try XCTUnwrapCheck(model.tasks.first { $0.title == "見積もりを確認" }, "estimate task")
    // Undo straight away, before the completion write returns: the undo must still land last.
    model.complete(estimate)
    try check(model.isCompleted(estimate), "Completing must show the task as done immediately")
    try snapshot(model, "completing")
    model.undoCompletion(estimate)
    try waitFor("undo write") { !model.isCompleted(estimate) && model.saving.isEmpty }
    pages = try fixturePages(fixture)
    try check(pages[estimate.id]?["status"] as? String == "o2", "Undo must restore the previous status option")
    try check(model.tasks.contains { $0.id == estimate.id }, "Undone task must stay in the list")
    let report = try XCTUnwrapCheck(model.tasks.first { $0.title == "週次レポート" }, "report task")
    model.complete(report)
    try waitFor("task removed after undo window", seconds: NotionTasksModel.undoSeconds + 8) { !model.tasks.contains { $0.id == report.id } }
    let reportStatus = try fixturePages(fixture)[report.id]?["status"] as? String
    try check(reportStatus == "o3", "Completed task must stay done in Notion")
    let share = try XCTUnwrapCheck(model.tasks.first { $0.title == "資料を共有" }, "share task")
    model.save(share, title: "資料を共有（改訂）", due: .some(nil))
    try waitFor("edit") { model.tasks.contains { $0.id == share.id && $0.title == "資料を共有（改訂）" && $0.due == nil } }
    pages = try fixturePages(fixture)
    try check(pages[share.id]?["title"] as? String == "資料を共有（改訂）" && pages[share.id]?["due"] is NSNull,
              "Editing must rename and clear the due date in Notion")

    // Filters: text, a tag column, assignees; saved filters survive the panel URL.
    var savedFilter: NotionTaskFilter?
    model.onFilterChange = { savedFilter = $0 }
    func visible() -> [String] { model.visibleTasks(now: Date()).map(\.title) }
    model.filterText = "資料"
    try check(visible() == ["資料を共有（改訂）"], "Text filter must narrow by task name: \(visible())")
    try check(savedFilter == nil, "The text filter is not saved")
    model.filterText = ""
    try check(model.filterProperties.contains { $0.id == "tg" }, "Tag columns must be offered as filters")
    if let status = model.schema?.property("%3AUPp") {
        try check(model.filterOptions(status).map(\.id) == ["o1", "o2"], "Complete statuses must not be offered for open tasks")
    }
    model.toggleChoice("t2", of: "tg")
    try check(visible() == ["見積もりを確認"], "Tag filter must keep matching tasks: \(visible())")
    try check(savedFilter?.choiceValues == ["t2"] && savedFilter?.choiceProperty == "tg", "Changing filters must save them to the panel")
    try check(WidgetSpec(url: WidgetSpec(kind: .notionTasks, notionTasks: model.mapping, notionFilter: model.filter).url)?.notionFilter == model.filter,
              "Saved filters must survive the panel URL")
    try snapshot(model, "filtered")
    model.showingFilters = true
    try snapshot(model, "filters")
    model.showingFilters = false
    model.toggleChoice("t2", of: "tg")
    try check(Set(model.knownPeople.map(\.id)) == ["u1", "u2"] && model.mapping?.assigneeProperty == "pp", "Assignees must come from the people column")
    model.togglePerson("u1")
    try check(visible() == ["資料を共有（改訂）"], "Assignee filter must keep that person's tasks: \(visible())")
    model.filter.due = .none
    try check(visible() == ["資料を共有（改訂）"], "Due filters combine with assignee filters")
    model.clearFilters()
    try check(!model.filter.isActive && visible().count == model.tasks.count && savedFilter == NotionTaskFilter(), "Clearing must remove every filter")

    // An opened task: content across pages of results, nested children, edits that reach Notion.
    let shared = try XCTUnwrapCheck(model.tasks.first { $0.id == share.id }, "share task after edit")
    model.openDetail(shared)
    let detail = try XCTUnwrapCheck(model.detail, "opened task")
    try waitFor("page content") { detail.loaded }
    try check(detail.blocks.map(\.id) == ["b-h", "b-p", "b-bold", "b-todo", "b-list", "b-n1", "b-n2", "b-img", "b-child", "b-form"],
              "Every top-level block must load across result pages: \(detail.blocks.map(\.id))")
    try check(NotionBlock.find("b-nested", in: detail.blocks)?.plainText == "営業チーム", "Nested list items must load")
    func block(_ id: String) throws -> NotionBlock { try XCTUnwrapCheck(NotionBlock.find(id, in: detail.blocks), id) }
    let plain = try block("b-p"), formatted = try block("b-bold"), image = try block("b-img")
    try check(plain.isEditable && !formatted.isEditable && !image.isEditable, "Only unformatted text blocks may be edited")
    try snapshot(model, "detail")
    detail.beginEdit(try block("b-bold"))
    try check(detail.editingBlock == nil, "Formatted blocks must stay read-only")
    detail.beginEdit(try block("b-p"))
    detail.blockDraft = "資料をまとめて共有する"
    detail.saveBlock()
    try waitFor("block text saved") { (try? fixtureBlocks(fixture))?["b-p"]?["text"] as? String == "資料をまとめて共有する" }
    let edited = try block("b-p")
    try check(edited.plainText == "資料をまとめて共有する", "Edited text must show in the panel")
    detail.toggleChecked(try block("b-todo"))
    try waitFor("to-do checked") { (try? fixtureBlocks(fixture))?["b-todo"]?["checked"] as? Bool == true }
    detail.append("追加の確認", kind: .todo)
    try waitFor("block appended") { detail.blocks.last?.plainText == "追加の確認" && detail.blocks.last?.kind == .todo }
    let blocksAfterAppend = try fixtureBlocks(fixture)
    try check(blocksAfterAppend.values.contains { $0["type"] as? String == "to_do" && $0["text"] as? String == "追加の確認" },
              "Appended blocks must reach Notion at the end of the page")
    let second = try block("b-n2")
    detail.delete(second)
    try check(detail.confirmingDelete == "b-n2" && NotionBlock.find("b-n2", in: detail.blocks) != nil, "Deleting must ask first")
    detail.delete(second)
    try waitFor("block deleted") { NotionBlock.find("b-n2", in: detail.blocks) == nil && (try? fixtureBlocks(fixture))?["b-n2"] == nil }
    detail.setStatus("o2")
    try waitFor("status changed") { detail.task.statusOptionID == "o2" && model.tasks.first { $0.id == share.id }?.statusOptionID == "o2" }
    let statusAfter = try fixturePages(fixture)[share.id]?["status"] as? String
    try check(statusAfter == "o2", "Status changes must reach Notion")
    detail.beginTitleEdit(); detail.titleDraft = "資料を共有（最終）"; detail.saveTitle()
    try waitFor("title changed") { model.tasks.contains { $0.id == share.id && $0.title == "資料を共有（最終）" } }
    model.closeDetail()
    try check(model.detail == nil, "Closing must return to the list")
    model.setActive(false)

    // Checkbox database: pagination and checkbox completion.
    let checkboxModel = NotionTasksModel(mapping: NotionTaskMapping(dataSourceID: "ds-checkbox", name: "チーム タスク",
                                                                    titleProperty: "title", completion: .checkbox(property: "chk")))
    checkboxModel.setActive(true)
    try waitFor("checkbox tasks") { checkboxModel.lastLoaded != nil && !checkboxModel.loading }
    try check(checkboxModel.tasks.count == 5, "Every page of open checkbox tasks must load: \(checkboxModel.tasks.count)")
    let first = checkboxModel.tasks[0]
    checkboxModel.complete(first)
    try waitFor("checkbox write") { (try? fixturePages(fixture))?[first.id]?["checked"] as? Bool == true }
    checkboxModel.undoCompletion(first)
    try waitFor("checkbox undo") { (try? fixturePages(fixture))?[first.id]?["checked"] as? Bool == false && checkboxModel.saving.isEmpty }
    checkboxModel.setActive(false)

    // New database under a page.
    let creator = NotionTasksModel(mapping: nil)
    var created: NotionTaskMapping?
    creator.onConfigurationChange = { created = $0 }
    creator.beginConfiguring()
    creator.showCreateDatabase()
    try waitFor("page search") { creator.searchResults.first?.kind == .page && !creator.searching }
    try snapshot(creator, "create-database")
    creator.newDatabaseTitle = "確認用タスク"
    creator.createDatabase(under: creator.searchResults[0])
    try waitFor("database creation") { creator.step == .mapColumns && creator.draft != nil && creator.draftSchema != nil }
    try check(creator.draftSchema?.title == "確認用タスク", "New database must use the chosen title")
    if case .checkbox = creator.draft?.completion {} else { throw NotionCheckError(description: "New database must complete with its checkbox") }
    try check(creator.draft?.dueProperty != nil, "New database must map its due date column")
    creator.finishConfiguring()
    try check(created != nil, "Creating a database must save the new mapping")
    creator.setActive(true)
    try waitFor("empty new database") { creator.lastLoaded != nil && !creator.loading }
    creator.add(title: "最初のタスク", due: nil)
    try waitFor("task in new database") { creator.tasks.map(\.title) == ["最初のタスク"] }
    creator.setActive(false)

    // A pasted database link or ID instead of search.
    let linker = NotionTasksModel(mapping: nil)
    linker.beginConfiguring()
    linker.linkText = "https://www.notion.so/acme/Project-1f2e3d4c5b6a79881f2e3d4c5b6a7988?v=0123456789abcdef0123456789abcdef"
    linker.openLink()
    try waitFor("database link with one data source") { linker.step == .mapColumns && linker.draft?.dataSourceID == "ds-status" }
    linker.showSourceList()
    linker.linkText = "2a2b2c2d-2e2f-3031-3233-343536373839"
    linker.openLink()
    try waitFor("database with several data sources") { linker.linkNote != nil && linker.searchResults.map(\.id) == ["ds-status", "ds-checkbox"] }
    linker.linkText = "https://app.notion.com/p/3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c"
    linker.openLink()
    try waitFor("data source ID pasted directly") { linker.step == .mapColumns && linker.draft?.dataSourceID == "3c3c3c3c-3c3c-3c3c-3c3c-3c3c3c3c3c3c" }
    linker.showSourceList()
    linker.linkText = "https://example.com/1f2e3d4c5b6a79881f2e3d4c5b6a7988"
    linker.openLink()
    try check(linker.setupError != nil && linker.step == .chooseSource, "Links outside Notion must be refused without a request")
    linker.linkText = "9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f"
    linker.openLink()
    try waitFor("unknown database") { linker.setupError?.contains("接続") == true }
    try snapshot(linker, "link-not-found")
    linker.cancelConfiguring()

    // Errors: hidden database, changed columns, bad token.
    let hidden = NotionTasksModel(mapping: NotionTaskMapping(dataSourceID: "ds-hidden", name: "", titleProperty: "title", completion: .checkbox(property: "c")))
    hidden.setActive(true)
    try waitFor("not shared error") { hidden.error != nil }
    try check(hidden.error?.status == 404 && hidden.error?.message.contains("接続") == true, "A database not shared with the token must explain how to connect it")
    try snapshot(hidden, "not-shared")
    hidden.setActive(false)
    let changed = NotionTasksModel(mapping: NotionTaskMapping(dataSourceID: "ds-status", name: "", titleProperty: "title",
                                                              completion: .status(property: "%3AUPp", done: "o3"), dueProperty: "removed"))
    changed.setActive(true)
    try waitFor("mapping problem") { changed.error != nil }
    try check(changed.error?.needsMapping == true && changed.setupError != nil, "A removed column must ask to redo the mapping")
    changed.setActive(false)
    NotionEnvironment.current = NotionEnvironment(tokens: MemoryNotionTokenStore("wrong"), baseURL: fixture)
    let unauthorized = NotionTasksModel(mapping: saved)
    unauthorized.setActive(true)
    try waitFor("unauthorized") { unauthorized.error != nil }
    try check(unauthorized.error?.status == 401, "An invalid token must be reported as such")
    unauthorized.setActive(false)

    // Settings: saving checks the token; the token lives only in the environment's store.
    NotionEnvironment.current = NotionEnvironment(tokens: MemoryNotionTokenStore(), baseURL: fixture)
    try snapshot(NotionTasksModel(mapping: saved), "no-token")
    let settings = SettingsController(store: SettingsStore(storage: MemorySettingsStorage()), permissionState: { false }, loginService: FakeLoginItemService())
    try check(!settings.notionHasToken, "Settings must start without a token")
    settings.saveNotionToken(" wrong ")
    try waitFor("bad token check") { !settings.notionChecking && settings.notionStatus != nil }
    try check(settings.notionStatus?.ok == false && settings.notionHasToken, "A failing token must be reported and kept for retry")
    settings.removeNotionToken()
    try check(!settings.notionHasToken, "Removing must delete the token")
    settings.saveNotionToken("fixture-token")
    try waitFor("good token check") { !settings.notionChecking && settings.notionStatus != nil }
    try check(settings.notionStatus?.ok == true && NotionEnvironment.current.tokens.token() == "fixture-token", "A valid token must be saved trimmed and confirmed")
    print("PASS: Notion setup (status + checkbox + new database + pasted link/ID), filters (text, tags, assignees, saved), opened task content (paged, nested, edit, to-do, append, delete, status, title), open-task filter, pagination, add, complete, undo, edit, 404/400/401 messages, token settings")
}

private func XCTUnwrapCheck<T>(_ value: T?, _ name: String) throws -> T {
    guard let value else { throw NotionCheckError(description: "Missing \(name)") }
    return value
}
