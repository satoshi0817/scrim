import AppKit
import SwiftUI
import ScrimCore

/// Native task list backed by one Notion data source. Reads open tasks, adds, completes (with undo) and edits.
@MainActor final class NotionTasksModel: ObservableObject {
    enum SetupStep: Equatable { case chooseSource, mapColumns, createDatabase }
    /// `write` reports whether Notion accepted the completion; `removal` hides the row after the undo window.
    struct PendingCompletion { var previousStatus: String?; var write: Task<Bool, Never>; var removal: Task<Void, Never> }

    @Published private(set) var mapping: NotionTaskMapping?
    @Published private(set) var schema: NotionDataSourceSchema?
    @Published private(set) var tasks: [NotionTask] = []
    @Published private(set) var completing: Set<String> = []
    @Published private(set) var saving: Set<String> = []
    @Published var error: NotionAPIError?
    @Published private(set) var loading = false
    @Published private(set) var hasToken = false
    @Published private(set) var lastLoaded: Date?
    // Setup
    @Published private(set) var isConfiguring = false
    @Published var step: SetupStep = .chooseSource
    @Published var searchQuery = ""
    /// A pasted database URL or ID, an alternative to searching.
    @Published var linkText = ""
    @Published private(set) var linkNote: String?
    @Published private(set) var searchResults: [NotionSearchResult] = []
    @Published private(set) var searching = false
    @Published var draft: NotionTaskMapping?
    @Published private(set) var draftSchema: NotionDataSourceSchema?
    @Published var newDatabaseTitle = NotionTaskDatabase.defaultTitle
    @Published var setupError: String?
    var onConfigurationChange: ((NotionTaskMapping) -> Void)?
    var onOpenPage: ((URL) -> Void)?
    // Filtering (applied to the loaded open tasks, so it is instant and costs no requests)
    @Published var filter: NotionTaskFilter { didSet { if filter != oldValue { onFilterChange?(filter) } } }
    @Published var filterText = ""
    @Published var showingFilters = false
    var onFilterChange: ((NotionTaskFilter) -> Void)?
    // The task opened in the panel, with its page content.
    @Published private(set) var detail: NotionTaskDetailModel?

    static let undoSeconds: Double = 4
    static let refreshInterval: TimeInterval = 60
    private var pending: [String: PendingCompletion] = [:]
    private var active = false
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var revision = 0
    private var tokenObserver: NSObjectProtocol?

    init(mapping: NotionTaskMapping?, filter: NotionTaskFilter = NotionTaskFilter()) {
        self.mapping = mapping; self.filter = filter
        hasToken = NotionEnvironment.current.hasToken
        tokenObserver = NotificationCenter.default.addObserver(forName: NotionEnvironment.tokenChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasToken = NotionEnvironment.current.hasToken
                self.schema = nil; self.error = nil
                if self.active { self.refresh(force: true) }
            }
        }
    }
    deinit {
        timer?.invalidate(); loadTask?.cancel(); searchTask?.cancel()
        if let tokenObserver { NotificationCenter.default.removeObserver(tokenObserver) }
    }
    private var client: NotionClient { NotionEnvironment.current.client }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value; timer?.invalidate(); timer = nil
        guard value else { revision += 1; loadTask?.cancel(); loadTask = nil; loading = false; return }
        hasToken = NotionEnvironment.current.hasToken
        if lastLoaded.map({ Date().timeIntervalSince($0) >= 30 }) ?? true { refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in if self?.active == true, self?.pending.isEmpty == true { self?.refresh() } }
        }
    }

    func refresh(force: Bool = false) {
        guard let mapping, hasToken, !isConfiguring else { return }
        if loadTask != nil && !force { return }
        loadTask?.cancel()
        revision += 1; let token = revision
        loading = true
        let client = self.client, cachedSchema = force ? nil : schema
        loadTask = Task { [weak self] in
            do {
                let schema: NotionDataSourceSchema
                if let cachedSchema { schema = cachedSchema } else { schema = try await client.schema(mapping.dataSourceID) }
                if let problem = schema.mappingProblem(mapping) {
                    guard let self, token == self.revision else { return }
                    self.schema = schema; self.tasks = []; self.error = NotionAPIError(status: 400, code: "validation_error")
                    self.setupError = problem; self.loading = false; self.loadTask = nil; return
                }
                let tasks = try await client.openTasks(mapping, schema: schema)
                guard let self, token == self.revision, !Task.isCancelled else { return }
                self.schema = schema
                // Keep tasks that are still inside their undo window.
                let fetched = Set(tasks.map(\.id))
                let kept = self.tasks.filter { self.pending[$0.id] != nil && !fetched.contains($0.id) }
                self.tasks = NotionTask.ordered(tasks + kept)
                self.error = nil; self.lastLoaded = Date()
            } catch is CancellationError {
            } catch {
                guard let self, token == self.revision else { return }
                self.error = error as? NotionAPIError ?? .network
                if self.error?.needsMapping == true { self.schema = nil }
            }
            if let self, token == self.revision { self.loading = false; self.loadTask = nil }
        }
    }

    // MARK: Tasks

    func isCompleted(_ task: NotionTask) -> Bool { completing.contains(task.id) }

    // MARK: Filters

    /// Tasks that pass the filters. Rows in their undo window stay visible.
    func visibleTasks(now: Date) -> [NotionTask] {
        tasks.filter { completing.contains($0.id) || filter.matches($0, text: filterText, assigneeProperty: mapping?.assigneeProperty, now: now) }
    }
    var isFiltering: Bool { filter.isActive || !filterText.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Status, select and multi-select columns to filter by; complete statuses never appear among open tasks.
    var filterProperties: [NotionProperty] { schema?.choiceProperties.filter { !filterOptions($0).isEmpty } ?? [] }
    func filterOptions(_ property: NotionProperty) -> [NotionProperty.Option] {
        guard let mapping, let schema, case .status(let id, _) = mapping.completion, id == property.id else { return property.options }
        let complete = Set(schema.completeOptionIDs(mapping))
        return property.options.filter { !complete.contains($0.id) }
    }
    /// Assignees seen on the loaded tasks.
    var knownPeople: [NotionChoice] {
        guard let property = mapping?.assigneeProperty else { return [] }
        var seen = Set<String>()
        return tasks.flatMap { $0.choices[property] ?? [] }.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }
    func toggleChoice(_ option: String, of property: String) {
        var next = filter
        if next.choiceProperty != property { next.choiceProperty = property; next.choiceValues = [] }
        if next.choiceValues.contains(option) { next.choiceValues.remove(option) } else { next.choiceValues.insert(option) }
        if next.choiceValues.isEmpty { next.choiceProperty = nil }
        filter = next
    }
    func togglePerson(_ id: String) {
        if filter.people.contains(id) { filter.people.remove(id) } else { filter.people.insert(id) }
    }
    func clearFilters() { filter = NotionTaskFilter(); filterText = "" }
    /// One line describing the saved filters, for the list header.
    var filterSummary: String? {
        guard filter.isActive else { return nil }
        var parts: [String] = []
        if filter.due != .all { parts.append(filter.due.title) }
        if let id = filter.choiceProperty, let property = schema?.property(id) {
            let names = property.options.filter { filter.choiceValues.contains($0.id) }.map(\.name)
            if !names.isEmpty { parts.append(property.name + "：" + names.joined(separator: "・")) }
        }
        if !filter.people.isEmpty {
            let names = knownPeople.filter { filter.people.contains($0.id) }.map(\.name)
            parts.append("担当：" + (names.isEmpty ? "\(filter.people.count)人" : names.joined(separator: "・")))
        }
        return parts.joined(separator: "、")
    }

    // MARK: Task detail

    func openDetail(_ task: NotionTask) {
        guard let mapping else { return }
        let detail = NotionTaskDetailModel(task: task, mapping: mapping, schema: schema)
        detail.onTaskChange = { [weak self] updated in self?.replace(updated) }
        detail.onOpenPage = { [weak self] url in self?.onOpenPage?(url) }
        detail.onComplete = { [weak self] (task: NotionTask) in self?.closeDetail(); self?.complete(task) }
        self.detail = detail
        detail.load()
    }
    func closeDetail() { detail?.cancel(); detail = nil }

    /// Marks the task done in Notion right away; it disappears after the undo window.
    func complete(_ task: NotionTask) {
        guard let mapping, pending[task.id] == nil else { return }
        completing.insert(task.id)
        let client = self.client, previous = task.statusOptionID
        // The write is never cancelled, so an undo always lands after it in Notion.
        let write = Task { [weak self] () -> Bool in
            do { _ = try await client.update(task.id, mapping, completed: true); return true }
            catch {
                guard let self else { return false }
                self.pending[task.id]?.removal.cancel()
                self.pending[task.id] = nil; self.completing.remove(task.id)
                self.error = error as? NotionAPIError ?? .network
                return false
            }
        }
        let removal = Task { [weak self] in
            guard await write.value else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.undoSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.pending[task.id] != nil else { return }
            self.pending[task.id] = nil; self.completing.remove(task.id)
            withAnimation(.easeOut(duration: 0.2)) { self.tasks.removeAll { $0.id == task.id } }
        }
        pending[task.id] = PendingCompletion(previousStatus: previous, write: write, removal: removal)
    }

    func undoCompletion(_ task: NotionTask) {
        guard let mapping, let entry = pending.removeValue(forKey: task.id) else { return }
        entry.removal.cancel()
        let client = self.client
        saving.insert(task.id)
        Task { [weak self] in
            // Nothing to undo if Notion never recorded the completion.
            if await entry.write.value {
                do {
                    let restored = try await client.update(task.id, mapping, completed: false, restoreStatusOptionID: entry.previousStatus)
                    self?.replace(restored)
                } catch {
                    self?.error = error as? NotionAPIError ?? .network
                }
            }
            self?.completing.remove(task.id); self?.saving.remove(task.id)
        }
    }

    func add(title: String, due: Date?) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mapping, !text.isEmpty else { return }
        let client = self.client, date = due.map { NotionDate(day: $0) }
        saving.insert("new")
        Task { [weak self] in
            do {
                let created = try await client.create(mapping, title: text, due: mapping.dueProperty == nil ? nil : date)
                guard let self else { return }
                self.tasks = NotionTask.ordered(self.tasks + [created]); self.error = nil
            } catch {
                guard let self else { return }
                self.error = error as? NotionAPIError ?? .network
            }
            self?.saving.remove("new")
        }
    }

    /// `due` nil leaves the date unchanged; `.some(nil)` clears it.
    func save(_ task: NotionTask, title: String, due: Date??) {
        guard let mapping else { return }
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = text.isEmpty || text == task.title ? nil : text
        var newDue: NotionDate?? = nil
        if mapping.dueProperty != nil, let due {
            let value = due.map { NotionDate(day: $0) }
            if value != task.due { newDue = .some(value) }
        }
        guard newTitle != nil || newDue != nil else { return }
        let client = self.client
        saving.insert(task.id)
        Task { [weak self] in
            do {
                let updated = try await client.update(task.id, mapping, title: newTitle, due: newDue)
                self?.replace(updated); self?.error = nil
            } catch {
                self?.error = error as? NotionAPIError ?? .network
            }
            self?.saving.remove(task.id)
        }
    }

    func open(_ task: NotionTask) { if let url = task.url { onOpenPage?(url) } }

    private func replace(_ task: NotionTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task } else { tasks.append(task) }
        tasks = NotionTask.ordered(tasks)
    }

    // MARK: Setup

    func beginConfiguring() {
        isConfiguring = true; setupError = nil
        draft = mapping; draftSchema = nil
        step = .chooseSource; searchQuery = ""
        search()
        if let mapping { chooseSource(mapping.dataSourceID, keeping: mapping) }
    }
    func cancelConfiguring() {
        isConfiguring = false; searchTask?.cancel(); setupError = nil
        if active { refresh(force: true) }
    }
    func search() {
        searchTask?.cancel()
        let kind: NotionSearchResult.Kind = step == .createDatabase ? .page : .dataSource
        let query = searchQuery, client = self.client
        searching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let results = try await client.search(kind, query: query)
                guard let self, !Task.isCancelled else { return }
                self.searchResults = results; self.setupError = nil
            } catch is CancellationError { return
            } catch {
                guard let self else { return }
                self.searchResults = []; self.setupError = (error as? NotionAPIError ?? .network).message
            }
            self?.searching = false
        }
    }
    /// Opens the database named by a pasted link or ID. One data source goes straight to column mapping;
    /// several are listed to choose from.
    func openLink() {
        guard let id = NotionLink.objectID(from: linkText) else {
            setupError = "NotionのデータベースのURL（「リンクをコピー」）かIDを入力してください。"; return
        }
        searchTask?.cancel()
        let client = self.client
        searching = true; setupError = nil; linkNote = nil
        searchTask = Task { [weak self] in
            do {
                let sources = try await client.dataSources(forLinkedID: id)
                guard let self, !Task.isCancelled else { return }
                self.searching = false
                switch sources.count {
                case 0: self.setupError = "このデータベースにはデータソースがありません。"
                case 1: self.chooseSource(sources[0].id)
                default:
                    self.searchResults = sources
                    self.linkNote = "このデータベースにはデータソースが複数あります。使うものを選んでください。"
                }
            } catch is CancellationError {
            } catch {
                guard let self else { return }
                self.searching = false
                let failure = error as? NotionAPIError ?? .network
                self.setupError = failure.status == 400
                    ? "データベースのURLではないようです。データベースを開いて「リンクをコピー」したURLを貼り付けてください。"
                    : failure.message
            }
        }
    }
    func showCreateDatabase() { step = .createDatabase; searchQuery = ""; search() }
    func showSourceList() { step = .chooseSource; searchQuery = ""; search() }

    func chooseSource(_ id: String, keeping existing: NotionTaskMapping? = nil) {
        let client = self.client
        setupError = nil
        Task { [weak self] in
            do {
                let schema = try await client.schema(id)
                guard let self else { return }
                self.draftSchema = schema
                if let existing, existing.dataSourceID == id, schema.mappingProblem(existing) == nil { self.draft = existing }
                else if let guess = schema.defaultMapping() { self.draft = guess }
                else {
                    self.draft = nil
                    self.setupError = "このデータベースには、完了に使えるチェックボックスかステータスの列がありません。列を追加するか、新しく作成してください。"
                    return
                }
                self.step = .mapColumns
            } catch {
                self?.setupError = (error as? NotionAPIError ?? .network).message
            }
        }
    }
    func createDatabase(under page: NotionSearchResult) {
        let client = self.client, title = newDatabaseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        searching = true; setupError = nil
        Task { [weak self] in
            do {
                let mapping = try await client.createTaskDatabase(parentPage: page.id, title: title.isEmpty ? NotionTaskDatabase.defaultTitle : title)
                guard let self else { return }
                self.draftSchema = try await client.schema(mapping.dataSourceID)
                self.draft = mapping; self.step = .mapColumns
            } catch {
                self?.setupError = (error as? NotionAPIError ?? .network).message
            }
            self?.searching = false
        }
    }
    func finishConfiguring() {
        guard let draft, let draftSchema, draftSchema.mappingProblem(draft) == nil else { return }
        // Saved filters refer to the old database's columns.
        if mapping?.dataSourceID != draft.dataSourceID { filter = NotionTaskFilter(); filterText = "" }
        else if let id = filter.choiceProperty, draftSchema.property(id) == nil { filter.choiceProperty = nil; filter.choiceValues = [] }
        if draft.assigneeProperty == nil { filter.people = [] }
        mapping = draft; schema = draftSchema; tasks = []; error = nil; setupError = nil
        isConfiguring = false
        onConfigurationChange?(draft)
        refresh(force: true)
    }
}

struct NotionTasksView: View {
    @ObservedObject var model: NotionTasksModel
    let now: Date
    let size: CGSize
    let editing: Bool
    @State private var newTitle = ""
    @State private var newDue: Date?
    @ObservedObject private var appearance = NotionAppearance.shared
    @FocusState private var focus: Field?
    enum Field: Hashable { case add }
    private var compact: Bool { size.height < 260 || size.width < 300 }

    var body: some View {
        Group {
            if model.isConfiguring { NotionTasksSetupView(model: model) }
            else if let detail = model.detail, !editing {
                NotionTaskDetailView(model: detail, now: now, close: { model.closeDetail() }).transition(.opacity)
            } else { list.transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.18), value: model.detail != nil)
        .animation(.easeOut(duration: 0.18), value: model.showingFilters)
        .padding(compact ? 14 : 18)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                Text(model.mapping?.name.isEmpty == false ? model.mapping!.name : "Notionタスク")
                    .font(.system(size: compact ? 16 : 18, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.loading { ProgressView().controlSize(.small) }
            if model.mapping != nil && model.hasToken && model.lastLoaded != nil {
                let open = model.tasks.count - model.completing.count
                let shown = model.visibleTasks(now: now).count - model.completing.count
                Text(model.isFiltering ? "\(shown)／\(open)件" : "\(open)件")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
        }
    }

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !model.hasToken {
                notice("Notionのトークンが未登録です。", detail: "設定 → パネル →「Notion」でトークンを登録してください。")
                Spacer(minLength: 0)
            } else if model.mapping == nil {
                notice("表示するデータベースが未設定です。", detail: editing ? "パネルをクリックして、メニューの「データベースと列を設定…」を選んでください。" : nil)
                if !editing { Button("データベースを設定…") { model.beginConfiguring() }.controlSize(.regular) }
                Spacer(minLength: 0)
            } else if model.showingFilters && !editing {
                NotionTaskFiltersView(model: model)
            } else {
                if let error = model.error { errorBanner(error) }
                if model.lastLoaded != nil { filterBar }
                let visible = model.visibleTasks(now: now)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { task in row(task).id(task.id) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
                .overlay {
                    if visible.isEmpty && model.error == nil && model.lastLoaded != nil {
                        Text(model.tasks.isEmpty ? "未完了のタスクはありません" : "条件に合うタスクはありません")
                            .font(.system(size: appearance.textSize.detail + 2)).foregroundStyle(.secondary)
                    }
                }
                // Adding needs a database that has loaded at least once.
                if !editing && model.lastLoaded != nil { addRow }
            }
        }
    }

    /// Text search plus the saved filters (due date, status/tags, assignee).
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("タスクを絞り込む", text: $model.filterText).textFieldStyle(.plain).font(.system(size: appearance.textSize.detail + 1))
                    if !model.filterText.isEmpty {
                        Button { model.filterText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("文字の絞り込みを消す")
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                Button { model.showingFilters = true } label: {
                    Image(systemName: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 17)).foregroundStyle(model.filter.isActive ? ScrimPalette.blue : Color.secondary)
                }
                .buttonStyle(.borderless).help("絞り込み").disabled(editing)
                .accessibilityLabel(model.filter.isActive ? "絞り込み（適用中）" : "絞り込み")
            }
            if let summary = model.filterSummary {
                HStack(spacing: 6) {
                    Text(summary).font(.system(size: appearance.textSize.detail)).foregroundStyle(ScrimPalette.blue).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("解除") { model.clearFilters() }.buttonStyle(.borderless).controlSize(.small).disabled(editing)
                }
            }
        }
    }

    private func notice(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .medium))
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func errorBanner(_ error: NotionAPIError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ScrimPalette.amber)
            Text(error.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if error.needsMapping && !editing { Button("設定") { model.beginConfiguring() }.controlSize(.small) }
            else if !editing { Button("再読み込み") { model.refresh(force: true) }.controlSize(.small) }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(ScrimPalette.amber.opacity(0.12)))
    }

    /// Click a task to open it in the panel; the circle completes it.
    private func row(_ task: NotionTask) -> some View {
        let done = model.isCompleted(task)
        let size = appearance.textSize
        let assignees = model.mapping?.assigneeProperty.flatMap { task.choices[$0] }?.map(\.name).filter { !$0.isEmpty } ?? []
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { model.complete(task) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: size.task + 2)).foregroundStyle(done ? ScrimPalette.blue : Color.secondary)
            }
            .buttonStyle(.plain).disabled(done || editing || model.saving.contains(task.id))
            .accessibilityLabel(done ? "完了済み" : "\(task.title)を完了にする")
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title.isEmpty ? "無題" : task.title)
                    .font(.system(size: size.task)).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                    .lineLimit(2)
                if task.due != nil || !assignees.isEmpty {
                    HStack(spacing: 10) {
                        if let due = task.due { NotionDueLabel(due: due, now: now, size: size.detail) }
                        if !assignees.isEmpty {
                            Label(assignees.joined(separator: "・"), systemImage: "person")
                                .font(.system(size: size.detail)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            if done {
                Button("元に戻す") { model.undoCompletion(task) }.buttonStyle(.borderless).controlSize(.small)
            } else if !editing {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if !done && !editing { model.openDetail(task) } }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if !done && !editing {
                Button("開く") { model.openDetail(task) }
                Button("完了にする") { model.complete(task) }
                Button("Notionで開く") { model.open(task) }.disabled(task.url == nil)
            }
        }
    }

    private func dueEditor(_ date: Binding<Date?>) -> some View {
        HStack(spacing: 4) {
            if let value = date.wrappedValue {
                DatePicker("期限", selection: Binding(get: { value }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).controlSize(.small)
                Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("期限を外す")
            } else {
                Button { date.wrappedValue = Calendar.current.startOfDay(for: now) } label: { Label("期限", systemImage: "calendar.badge.plus") }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").foregroundStyle(.secondary)
            TextField("タスクを追加", text: $newTitle).textFieldStyle(.plain).font(.system(size: appearance.textSize.task))
                .focused($focus, equals: .add)
                .onSubmit { submitNew() }
            if model.mapping?.dueProperty != nil { dueEditor($newDue) }
            if model.saving.contains("new") { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
    private func submitNew() {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.add(title: newTitle, due: newDue)
        newTitle = ""; newDue = nil; focus = .add
    }
}

struct NotionTasksSetupView: View {
    @ObservedObject var model: NotionTasksModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("キャンセル") { model.cancelConfiguring() }.controlSize(.small)
            }
            if let error = model.setupError {
                Text(error).font(.system(size: 12)).foregroundStyle(ScrimPalette.red).fixedSize(horizontal: false, vertical: true)
            }
            switch model.step {
            case .chooseSource: sourceList
            case .createDatabase: pageList
            case .mapColumns: columns
            }
        }
    }
    private var title: String {
        switch model.step {
        case .chooseSource: return "データベースを選ぶ"
        case .createDatabase: return "新しいタスクDBを作る"
        case .mapColumns: return "列を対応付ける"
        }
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.step == .createDatabase ? "作成先のページを検索" : "データベースを検索", text: $model.searchQuery)
                .textFieldStyle(.plain).onChange(of: model.searchQuery) { model.search() }
            if model.searching { ProgressView().controlSize(.small) }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
    private func results(action: @escaping (NotionSearchResult) -> Void) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.searchResults) { result in
                    Button { action(result) } label: {
                        HStack {
                            Image(systemName: result.kind == .page ? "doc.text" : "tablecells").foregroundStyle(.secondary)
                            Text(result.title.isEmpty ? "無題" : result.title).lineLimit(1)
                            Spacer()
                        }.padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay {
            if model.searchResults.isEmpty && !model.searching && model.setupError == nil {
                Text(model.step == .createDatabase ? "接続が追加されたページがありません" : "接続が追加されたデータベースがありません")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("データベースのURLまたはID", text: $model.linkText).textFieldStyle(.roundedBorder)
                    .onSubmit { model.openLink() }
                Button("開く") { model.openLink() }
                    .disabled(model.linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let note = model.linkNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("または検索").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            searchField
            results { model.chooseSource($0.id) }
            HStack {
                Text("一覧にない場合は、Notionでデータベースの「•••」→「接続」からトークンの接続を追加してください。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("新しく作成…") { model.showCreateDatabase() }.controlSize(.small)
            }
        }
    }
    private var pageList: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("データベース名", text: $model.newDatabaseTitle).textFieldStyle(.roundedBorder)
            Text("「タスク名」「完了」「期限」の列を持つデータベースを、選んだページの中に作ります。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            searchField
            results { model.createDatabase(under: $0) }
            Button("既存のデータベースから選ぶ") { model.showSourceList() }.controlSize(.small)
        }
    }
    @ViewBuilder private var columns: some View {
        if let schema = model.draftSchema, let draft = model.draft {
            Form {
                LabeledContent("データベース", value: schema.title.isEmpty ? "無題" : schema.title)
                LabeledContent("タイトル", value: schema.property(draft.titleProperty)?.name ?? "—")
                Picker("完了の列", selection: Binding(get: { draft.completion.property }, set: { setCompletion($0, schema: schema) })) {
                    ForEach(schema.completionProperties) { property in
                        Text("\(property.name)（\(property.kind == .checkbox ? "チェックボックス" : "ステータス")）").tag(property.id)
                    }
                }
                if case .status(let id, let done) = draft.completion, let status = schema.property(id) {
                    Picker("完了にする値", selection: Binding(get: { done }, set: { model.draft?.completion = .status(property: id, done: $0) })) {
                        ForEach(status.options) { Text($0.name).tag($0.id) }
                    }
                }
                Picker("期限の列", selection: Binding(get: { draft.dueProperty ?? "" }, set: { model.draft?.dueProperty = $0.isEmpty ? nil : $0 })) {
                    Text("使わない").tag("")
                    ForEach(schema.dateProperties) { Text($0.name).tag($0.id) }
                }
                Picker("担当者の列", selection: Binding(get: { draft.assigneeProperty ?? "" }, set: { model.draft?.assigneeProperty = $0.isEmpty ? nil : $0 })) {
                    Text("使わない").tag("")
                    ForEach(schema.peopleProperties) { Text($0.name).tag($0.id) }
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
            HStack {
                Button("データベースを選び直す") { model.showSourceList() }.controlSize(.small)
                Spacer()
                Button("このデータベースを使う") { model.finishConfiguring() }.buttonStyle(.borderedProminent)
                    .disabled(schema.mappingProblem(draft) != nil)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func setCompletion(_ id: String, schema: NotionDataSourceSchema) {
        guard let property = schema.property(id) else { return }
        if property.kind == .checkbox { model.draft?.completion = .checkbox(property: id) }
        else if let done = NotionDataSourceSchema.defaultDoneOption(property) { model.draft?.completion = .status(property: id, done: done) }
    }
}
