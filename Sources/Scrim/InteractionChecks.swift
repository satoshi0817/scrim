import AppKit
import SwiftUI
import WebKit
import PDFKit
import ScrimCore

private enum CheckError: Error { case failed(String) }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckError.failed(message) }
}
private func waitFor(_ description: String, until predicate: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(15)
    while !predicate() {
        guard Date() < deadline else { throw CheckError.failed("Timed out: " + description) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}
private func javascript(_ script: String, in web: WKWebView) throws -> Any? {
    var complete = false; var result: Any?; var failure: Error?
    web.evaluateJavaScript(script) { value, error in result = value; failure = error; complete = true }
    try waitFor("JavaScript") { complete }
    if let failure { throw failure }
    return result
}

/// Deliver a pointer click to WebKit so the document receives a trusted DOM event.
private func clickElement(_ id: String, in web: WKWebView) throws {
    let coordinates = try javascript("""
        (() => {
            const element = document.getElementById('\(id)');
            element.scrollIntoView({block: 'center'});
            const rect = element.getBoundingClientRect();
            return [rect.left + rect.width / 2, rect.top + rect.height / 2];
        })()
        """, in: web) as? [CGFloat]
    guard let coordinates, coordinates.count == 2, let window = web.window else {
        throw CheckError.failed("Missing click target: " + id)
    }
    let point = NSPoint(x: coordinates[0], y: web.isFlipped ? coordinates[1] : web.bounds.height - coordinates[1])
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = NSEvent.mouseEvent(with: type, location: web.convert(point, to: nil), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        if type == .leftMouseDown { web.mouseDown(with: event) } else { web.mouseUp(with: event) }
    }
}

/// Runs against a synthetic local server, memory settings, and an ephemeral cookie
/// store. No hotkey/permission registration, production preferences or accounts.
func verifyInteractions(fixture: URL) throws {
    for screen in [CGSize(width: 1512, height: 982), CGSize(width: 2560, height: 1440), CGSize(width: 3840, height: 2160)] {
        let grid = PanelGrid(screen: screen)
        let left = grid.frame(column: 0, row: 0, columns: 6, rows: 4)
        let right = grid.frame(column: 6, row: 0, columns: 6, rows: 4)
        try check(abs(right.minX-left.maxX-grid.gap) < 0.001, "Adjacent panels must have a gutter")
        try check(abs(left.minX-(screen.width-right.maxX)) < 0.001 && left.minX > 0, "Screen margins must be balanced")
    }
    let dataStore = WKWebsiteDataStore.nonPersistent()
    let store = SettingsStore(storage: MemorySettingsStorage())
    let controller = OverlayController(store: store, websiteDataStore: dataStore)
    controller.show(.pinned)
    defer { controller.show(.hidden, immediately: true) }
    try check(controller.root.subviews.compactMap { $0 as? OverlayControls }.first?.isHidden == true, "HUD must be hidden by default")
    controller.add(fixture)
    try check(controller.records.isEmpty, "Normal mode must reject additions")
    controller.setEditing(true); controller.add(fixture)
    try check(controller.records.count == 1, "Edit mode must accept additions")
    let record = controller.records[0]
    guard let view = controller.views[record.id] else { throw CheckError.failed("Missing panel") }
    view.frame = NSRect(x: 96, y: 144, width: 480, height: 336); view.layoutSubtreeIfNeeded()
    try check(view.editing && controller.root.editing, "Edit state must propagate")
    let hitPoint = NSPoint(x: view.frame.midX, y: view.frame.midY)
    try check(view.hitTest(hitPoint) === view, "Edit mode must intercept content drags")
    controller.setEditing(false)
    try check(!view.editing && !controller.root.editing, "Normal mode must lock layout")
    try check(view.web?.frame == view.bounds, "Page must fill panel without title bar")
    view.command?(3)
    try check(controller.records.count == 1, "Normal mode must reject panel closure")
    let initialFrame = view.frame
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 150), modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 300, y: 350), modifierFlags: [], timestamp: 1, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
    view.mouseDown(with: down); view.mouseDragged(with: drag); view.mouseUp(with: drag)
    try check(view.frame == initialFrame, "Normal mode drag must not change placement")
    controller.setEditing(true)
    let editDown = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: view.frame.midX, y: view.frame.midY), modifierFlags: [], timestamp: 2, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
    let editDrag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: view.frame.midX+200, y: view.frame.midY+200), modifierFlags: [], timestamp: 3, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 4, clickCount: 1, pressure: 1)!
    view.mouseDown(with: editDown); view.mouseDragged(with: editDrag); view.mouseUp(with: editDrag)
    try check(view.frame != initialFrame, "Edit mode must move panel")
    let grid = PanelGrid(screen: controller.root.bounds.size), step = grid.step
    let column = (view.frame.minX-grid.bounds.minX) / step.width, row = (view.frame.minY-grid.bounds.minY) / step.height
    try check(abs(column-column.rounded()) < 0.001 && abs(row-row.rounded()) < 0.001, "Movement must snap to display-relative grid")
    controller.setEditing(false)
    guard let web = view.web else { throw CheckError.failed("Missing WebKit view") }
    try waitFor("main page") { web.url?.path == "/login" && !web.isLoading }
    var opened: [URL] = []
    view.browser.openWebLink = { opened.append($0) }
    var expected: [URL] = []
    for (id, path) in [("normal", "/destination?source=panel%2Fweb#detail"),
                       ("blank", "/destination?source=blank#detail"), ("router", "/destination?source=router")] {
        expected.append(URL(string: path, relativeTo: fixture)!.absoluteURL)
        try clickElement(id, in: web)
        try waitFor(id + " link") { opened.count >= expected.count }
        try check(opened == expected && web.url == fixture && !view.browser.hasOpenWindows,
                  "Each link must open the original URL once and keep its panel on the original page: " + id)
    }
    controller.setEditing(true)
    view.command?(1)
    controller.setEditing(false)
    expected.append(fixture)
    try check(opened == expected, "The panel menu must use the same browser opener")
    try clickElement("fragment", in: web)
    try waitFor("same-page link") { web.url?.fragment == "login" }
    _ = try javascript("document.getElementById('login').click()", in: web)
    try waitFor("popup") { view.browser.popupWebViews.first?.url?.path == "/popup" && view.browser.popupWebViews.first?.isLoading == false }
    guard let popup = view.browser.popupWebViews.first else { throw CheckError.failed("Missing popup") }
    let text = try javascript("document.body.innerText", in: popup) as? String ?? ""
    try check(text.contains("テスト用ログイン"), "Popup must receive opener cookies")
    try clickElement("account", in: popup)
    try waitFor("account selection inside the login popup") {
        (try? javascript("document.body.dataset.account", in: popup) as? String) == "selected"
    }
    view.sleep()
    try check(view.web === web, "An OAuth opener must stay alive while popup is open")
    _ = try javascript("document.getElementById('continue').click()", in: popup)
    try waitFor("opener callback and redirect") { web.url?.path == "/signed-in" && !web.isLoading }
    let signedIn = try javascript("document.body.innerText", in: web) as? String ?? ""
    try check(signedIn.contains("signed-in"), "POST, redirect, HttpOnly cookies and opener messaging must work")
    let storageCallback = try javascript("localStorage.getItem('storageCallback')", in: web) as? String
    try check(storageCallback == "received", "Calendar-style storage callback must reach opener")
    try waitFor("window.close") { !view.browser.hasOpenWindows }
    try check(opened == expected, "Fragment, login, POST and redirects must stay in Scrim")
    view.reloadContent()
    try waitFor("restored session") { view.web?.isLoading == false && view.web?.url?.path == "/signed-in" }
    let restored = try javascript("document.body.innerText", in: view.web!) as? String ?? ""
    try check(restored.contains("signed-in"), "Recreated WebKit view must retain session")
    controller.setEditing(true)
    for _ in 0..<PanelPool.liveLimit { controller.add(fixture) }
    try waitFor("dormant WebKit panel") { view.web == nil }
    let preview = try view.subviews.compactMap { $0 as? NSImageView }.first.unwrap("Missing dormant preview")
    try check(!preview.isHidden && preview.image != nil, "Eviction must show a snapshot")
    controller.touch(record.id)
    try waitFor("wake after eviction") { view.web?.isLoading == false && view.web?.url?.path == "/signed-in" }
    try check(preview.isHidden && preview.image == nil, "The live WebView must release its previous snapshot")
    view.command?(3)
    try check(controller.views[record.id] == nil && controller.records.count == PanelPool.liveLimit, "Edit mode must close only the selected panel")
    try MainActor.assumeIsolated { try verifyWebRelease(fixture: fixture) }
    print("PASS: regular, target-blank, router and menu links; same-page anchor; mode lock, grid drag, edit-only add/close, OAuth popup, cookies, POST redirect, opener + storage callbacks, window.close, session restoration")
}

func inspectCalendarLogin() throws {
    let controller = OverlayController(store: SettingsStore(storage: MemorySettingsStorage()), websiteDataStore: .nonPersistent())
    controller.show(.pinned); controller.setEditing(true); controller.add(URL(string: "https://calendar.notion.com")!); controller.setEditing(false)
    defer { controller.show(.hidden, immediately: true) }
    guard let view = controller.views.values.first, let web = view.web else { throw CheckError.failed("Missing calendar WebKit view") }
    try waitFor("Calendar loading") { web.url?.host == "calendar.notion.com" && !web.isLoading }
    do {
        try waitFor("Calendar interface") {
            let text = (try? javascript("document.body.innerText", in: web)) as? String ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).count > 30
        }
    } catch {
        print("Public page diagnostic: \(web.url?.absoluteString ?? "none")")
        print(try javascript("document.body.innerText", in: web) as? String ?? "")
        throw error
    }
    print("Calendar public page in WKWebView:")
    print(try javascript("document.body.innerText", in: web) as? String ?? "")
}

/// Per-display mode shares content and keeps geometry per display; switching carries the latest arrangement.
func verifyDisplayLayoutModes() throws {
    let canvas = CGSize(width: 1600, height: 1000), small = CGSize(width: 1200, height: 750)
    let store = SettingsStore(storage: MemorySettingsStorage())
    store.panels = (0..<3).map {
        PanelRecord(url: URL(string: "https://example.invalid/\($0)")!,
                    placement: FractionalFrame(frame: CGRect(x: 20 + $0 * 520, y: 300, width: 480, height: 320), screen: canvas))
    }
    store.sharedLayoutReferenceSize = canvas
    let shared = store.layout(for: "uuid:a", screen: canvas)
    store.setSameLayoutOnAllDisplays(false)
    try check(LayoutFitter.frames(layout: store.layout(for: "uuid:a", screen: small), screen: small)
              == LayoutFitter.relativeFrames(layout: shared, screen: small),
              "Turning per-display layouts on must keep each display looking like the shared layout")
    var a = store.layout(for: "uuid:a", screen: canvas)
    a.panels[0].placement = FractionalFrame(frame: CGRect(x: 40, y: 40, width: 400, height: 300), screen: canvas)
    a.panels.removeLast()
    let added = PanelRecord(url: URL(string: "https://example.invalid/added")!,
                            placement: FractionalFrame(frame: CGRect(x: 900, y: 500, width: 400, height: 300), screen: canvas))
    a.panels.append(added)
    store.saveLayout(a, for: "uuid:a")
    let b = store.layout(for: "uuid:b", screen: canvas)
    try check(b.panels.map(\.id) == a.panels.map(\.id), "Adding or removing a panel on one display must apply to every display")
    try check(b.panels[0].placement == shared.panels[0].placement && store.layout(for: "uuid:a", screen: canvas).panels[0].placement == a.panels[0].placement,
              "Moving a panel on one display must not move it on another")
    var layouts = store.layoutsByDisplay
    try check(layouts["uuid:a"]?.editedAt != nil, "Moving a panel must mark the display as edited")
    layouts["uuid:a"]?.editedAt = Date(timeIntervalSince1970: 100)
    store.layoutsByDisplay = layouts
    store.setSameLayoutOnAllDisplays(true)
    try check(store.panels.map(\.placement) == a.panels.map(\.placement) && store.layoutsByDisplay.isEmpty,
              "Sharing again must adopt the most recently edited display's arrangement")
}

func verifyNativeSettings() throws {
    let store = SettingsStore(storage: MemorySettingsStorage())
    let login = FakeLoginItemService()
    let controller = SettingsController(store: store, permissionState: { true }, loginService: login)
    var dockChanges = 0, layoutChanges = 0, gestureChanges = 0
    controller.dockChanged = { dockChanges += 1 }
    controller.changed = { layoutChanges += 1 }
    controller.gestureChanged = { gestureChanges += 1 }
    controller.setDockVisible(true)
    try check(store.dockVisible && dockChanges == 1, "Native Dock switch must update model and callback")
    controller.setLoginEnabled(true)
    try check(controller.loginModel.isOn && login.registerCalls == 1, "Native login switch must use injected service")
    controller.setSameLayout(false)
    try check(!store.sameLayoutOnAllDisplays && layoutChanges == 1, "Native layout switch must update model and callback")
    controller.setShowsOverlay(false, on: "uuid:check")
    try check(!store.showsOverlay(on: "uuid:check") && store.showsOverlay(on: "uuid:other"), "Native display switch must turn the overlay off for that display only")
    controller.setShowsOverlay(true, on: "uuid:check")
    try verifyDisplayLayoutModes()
    controller.updateGesture { $0.command = .right; $0.enabled = false }
    try check(store.gesture.command == .right && !store.gesture.enabled && gestureChanges == 1, "Native gesture controls must update settings")
    controller.updateTiming(\.gapMax, value: 0.55)
    controller.updateTiming(\.gapMax, value: .nan)
    controller.updateTiming(\.gapMax, value: -1)
    try check(store.gesture.gapMax == 0.55, "Timing controls must reject invalid numbers")
    controller.registerShortcut = { _ in .success }
    controller.beginRecording(installMonitor: false); controller.receiveShortcut(.testCopy)
    try check(store.shortcut == .testCopy && !controller.isRecording, "Native shortcut controls must commit confirmed shortcuts")
    controller.registerShortcut = { .carbonFailure(shortcut: $0, status: -9878) }
    controller.beginRecording(installMonitor: false); controller.receiveShortcut(.default)
    try check(store.shortcut == .testCopy, "Failed registration must retain saved shortcut")
    controller.cancelRecording()
    try check(!controller.isRecording, "Cancellation must finish recording")
    try check(!store.showsOverlayControls, "HUD preference must default off")
    controller.setOverlayControlsVisible(true)
    try check(store.showsOverlayControls && layoutChanges == 2, "HUD preference must update settings and callback")
    var gesture = store.gesture; gesture.enabled = true; store.gesture = gesture
    controller.gestureAvailable = { false }
    try check(controller.monitoringStatus == "監視を開始できません", "Permission alone must not be reported as active monitoring")
    let retries = gestureChanges
    controller.retryMonitoring()
    try check(gestureChanges == retries+1, "Reconnect button must restart the monitor")
    controller.gestureAvailable = { true }
    try check(controller.monitoringStatus == "動作中", "Healthy monitoring must be distinguished from permission")
    let originalPageKeys = store.pageArrowModifiers
    func record(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, _ code: UInt16) {
        controller.recordPageKey(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: controller.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
    }
    controller.beginPageKeyRecording()
    record(.flagsChanged, .control, 59)
    record(.keyDown, [], 53)
    try check(!controller.recordingPageKeys && store.pageArrowModifiers == originalPageKeys, "Escape must discard the recorded modifiers")
    controller.beginPageKeyRecording()
    record(.flagsChanged, .option, 58)
    record(.flagsChanged, [.option, .shift], 56)
    record(.flagsChanged, .shift, 58)
    record(.flagsChanged, [], 56)
    try check(!controller.recordingPageKeys && store.pageArrowModifiers == NSEvent.ModifierFlags([.option, .shift]).rawValue, "Releasing the chord must save both modifiers")
    print("PASS: native settings bindings, Dock callback, login service, layout callback, gesture controls, timing validation, shortcut success/failure/cancel")
}

func verifyInputMonitoringRecovery() throws {
    final class Permission: GesturePermissionChecking {
        var granted = false
        func isGranted() -> Bool { granted }
    }
    final class Tap: GestureEventTap {
        var healthy = false
        var succeeds = true
        var connects = 0
        var disabled: (() -> Void)?
        func connect(receive: @escaping (CGEventType, CGEvent) -> Void, disabled: @escaping () -> Void) {
            connects += 1; healthy = succeeds; self.disabled = disabled
        }
        func disconnect() { healthy = false; disabled = nil }
        func timeout() { let callback = disabled; healthy = false; callback?() }
    }
    var now: Double = 0, secure = false
    let permission = Permission(), tap = Tap()
    let input = DoublePressInput(permission: permission, eventTap: tap, independentApp: { true }, secureInput: { secure }, clock: { now })
    input.start(settings: GestureSettings(), installTimer: false)
    try check(!input.available && tap.connects == 0, "An ungranted monitor must not attempt tap creation")
    permission.granted = true; now = 1; input.poll()
    try check(input.available && tap.connects == 1, "Granting permission must reconnect without relaunch")
    tap.healthy = false; now = 2; input.poll()
    try check(input.available && tap.connects == 2, "A stripped/disabled tap must be recreated")
    tap.timeout(); now = 2.5; input.poll()
    try check(!input.available && tap.connects == 2, "Timeout retries must be rate limited")
    now = 3.1; input.poll()
    try check(input.available && tap.connects == 3, "Timeout must recover after the retry interval")
    permission.granted = false; now = 4.2; input.poll()
    try check(!input.available && tap.connects == 3, "Revoked permission must stop monitoring")
    permission.granted = true; now = 5.3; input.poll()
    try check(input.available && tap.connects == 4, "Re-granting must recover")
    secure = true; now = 5.4; input.poll()
    try check(input.secure, "Secure input status must update promptly")
    input.stop(); now = 8; input.poll()
    try check(!input.available && tap.connects == 4, "Stopped monitors must stay stopped")
    let inherited = DoublePressInput(permission: permission, eventTap: tap, independentApp: { false })
    inherited.start(settings: GestureSettings(), installTimer: false)
    try check(tap.connects == 4, "CLI/host permission must never authorize monitoring")
    tap.succeeds = false; now = 10
    input.start(settings: GestureSettings(), installTimer: false)
    try check(!input.available, "A created but unhealthy tap must not be marked active")
    let attempts = tap.connects; now = 10.1; input.poll()
    try check(tap.connects == attempts, "Failed tap creation must not spin")
    print("PASS: grant/revoke/re-grant, effective tap failure, timeout recovery, retry limiting, secure input, stop, CLI isolation; no OS permission changes")
}

private func verifyNoteEditing(in directory: URL) throws {
    let files = PanelDocumentStorage(directory: directory)
    let controller = OverlayController(store: SettingsStore(storage: MemorySettingsStorage()), websiteDataStore: .nonPersistent(), documentStorage: files)
    controller.show(.pinned, immediately: true)
    defer { controller.show(.hidden, immediately: true) }
    controller.setEditing(true)
    controller.addNote()
    let panel = try controller.views.values.first.unwrap("Missing new note")
    func noteView(_ panel: PanelView) throws -> NativeNotePanel {
        try panel.subviews.compactMap { $0 as? NativeNotePanel }.first.unwrap("Missing native note editor")
    }
    let memo = try noteView(panel), editor = memo.editor
    try check(!controller.editing && editor.isEditable && controller.panel.firstResponder === editor, "Adding a note must focus its body")
    func press(_ format: NoteFormat) throws {
        let button = try memo.subviews.compactMap { $0 as? NSButton }.first(where: { $0.toolTip == format.label }).unwrap("Missing note format button")
        button.performClick(nil)
    }
    func type(_ text: String, in view: NSTextView) { view.insertText(text, replacementRange: view.selectedRange()) }
    func list(at word: String, in text: NSAttributedString) -> NSTextList? {
        let index = (text.string as NSString).range(of: word).location
        guard index != NSNotFound else { return nil }
        return (text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)?.textLists.last
    }
    try press(.numbers)
    type("牛乳", in: editor)
    editor.insertNewline(nil)
    type("卵", in: editor)
    let numbered = try list(at: "卵", in: memo.note.text).unwrap("Return must continue an ordered list")
    try check(numbered.isOrdered && memo.note.text.itemNumber(in: numbered, at: (editor.string as NSString).range(of: "卵").location) == 2,
              "The second item must be numbered 2")
    editor.insertNewline(nil)
    editor.insertNewline(nil)
    type("買い物メモ", in: editor)
    try check(list(at: "買い物メモ", in: memo.note.text) == nil, "Return on a blank item must finish the list")
    editor.setSelectedRange((editor.string as NSString).range(of: "牛乳\n卵"))
    try press(.bullets)
    try check(list(at: "牛乳", in: memo.note.text)?.isOrdered == false && list(at: "卵", in: memo.note.text)?.isOrdered == false,
              "The toolbar must convert all selected paragraphs to bullets")
    try press(.bullets)
    try check(list(at: "牛乳", in: memo.note.text) == nil, "Pressing the active list style must restore plain paragraphs")
    try press(.numbers)
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    try press(.bullets)
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    memo.note.undo.undo()
    try check(list(at: "卵", in: memo.note.text)?.isOrdered == true && memo.note.undo.canRedo, "Undo must restore the preceding list style")
    memo.note.undo.redo()
    try check(list(at: "卵", in: memo.note.text)?.isOrdered == false, "Redo must restore bullets")
    try press(.numbers)
    editor.setSelectedRange((editor.string as NSString).range(of: "買い物メモ"))
    try press(.bold)
    try press(.underline)
    try waitFor("formatted note autosave") {
        guard let saved = try? PanelDocumentStorage.readText(at: panel.url), saved.string == editor.string,
              let font = saved.attribute(.font, at: editor.selectedRange().location, effectiveRange: nil) as? NSFont else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask) &&
            saved.attribute(.underlineStyle, at: editor.selectedRange().location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue &&
            list(at: "卵", in: saved)?.isOrdered == true
    }
    try MainActor.assumeIsolated {
        let storage = MemorySettingsStorage()
        let store = SettingsStore(storage: storage)
        let appearance = PanelTextAppearance.shared
        defer { appearance.setNoteSize(.standard, in: store); appearance.setNotionSize(.standard, in: store) }
        let scroll = try (editor.enclosingScrollView).unwrap("Missing note scroll view")
        let selection = editor.selectedRange()
        let content = NSAttributedString(attributedString: memo.note.text)
        let saved = try Data(contentsOf: panel.url)
        let defaultSize = PanelTextSize.standard
        try check(store.noteTextSize == defaultSize && store.notionTextSize == defaultSize &&
                  defaultSize.noteMagnification == 1 && defaultSize.task == 15 && defaultSize.detail == 12 && defaultSize.body == 14,
                  "Medium must keep the previous note and task sizes")
        for size in PanelTextSize.allCases {
            appearance.setNoteSize(size, in: store)
            memo.layoutSubtreeIfNeeded()
            try check(abs(scroll.magnification - size.noteMagnification) < 0.001 &&
                      abs(editor.frame.width - scroll.contentView.bounds.width) < 1,
                      "Note size \(size) must wrap within the visible editor: magnification \(scroll.magnification), width \(editor.frame.width), viewport \(scroll.contentView.bounds.width)")
            try check(editor.selectedRange() == selection && memo.note.text.isEqual(to: content),
                      "Changing note size must preserve the selection and every rich-text attribute")
        }
        appearance.setNotionSize(.extraSmall, in: store)
        let restored = SettingsStore(storage: storage)
        let data = try Data(contentsOf: panel.url)
        try check(restored.noteTextSize == .extraLarge && restored.notionTextSize == .extraSmall && data == saved,
                  "Note and task sizes must persist independently; the RTF must stay intact")
        restored.notionTextSize = .large
        appearance.load(from: restored)
        try check(appearance.notionSize == .large && appearance.noteSize == .extraLarge,
                  "Loading preferences must retain existing task size selections")
    }
    controller.setEditing(true)
    try check(!editor.isEditable && controller.panel.firstResponder !== editor, "Moving a panel must release text input")
    panel.command?(2)
    let duplicate = try controller.views.values.first(where: { $0.id != panel.id }).unwrap("Missing duplicate note")
    let second = try noteView(duplicate)
    try check(second.note === memo.note, "Duplicate panels must share their document")
    duplicate.command?(4)
    try check(controller.panel.firstResponder === second.editor, "Edit note from the layout menu must focus the chosen copy")
    second.editor.setSelectedRange(NSRange(location: 0, length: 0))
    type("今週の", in: second.editor)
    try check(editor.string == second.editor.string && editor.string.hasPrefix("今週の"), "Edits must reach both copies")
    controller.show(.hidden, immediately: true)
    let reopened = try PanelNotes(files: files).open(panel.url)
    try check(reopened.text.string == editor.string && list(at: "卵", in: reopened.text)?.isOrdered == true,
              "Hiding immediately after typing must save text and formatting for the next launch")

    let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let legacyURL = folder.appendingPathComponent("note.txt"), original = "以前のメモ 👋"
    try original.write(to: legacyURL, atomically: true, encoding: .utf8)
    controller.show(.pinned, immediately: true)
    controller.setEditing(true)
    controller.add(legacyURL)
    let legacy = try controller.views.values.first(where: { $0.url == legacyURL }).unwrap("Missing legacy note")
    legacy.command?(4)
    let legacyEditor = try noteView(legacy).editor
    try check(legacyEditor.string == original && files.contentURL(for: legacyURL) == legacyURL, "Reading a legacy note must preserve the original file")
    legacyEditor.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
    type(" 追記", in: legacyEditor)
    legacy.sleep()
    let migrated = try PanelNotes(files: files).open(legacyURL)
    let originalFile = try String(contentsOf: legacyURL)
    try check(originalFile == original && migrated.text.string == original + " 追記" && files.contentURL(for: legacyURL).pathExtension == "rtf",
              "Legacy layout URLs must reopen rich notes and preserve the original UTF-8")
    let external = directory.deletingLastPathComponent().appendingPathComponent("external-note.rtf")
    let linkURL = URL(string: "https://example.org/reference#note")!
    let source = NSAttributedString(string: "外部ファイルの本文", attributes: [.link: linkURL])
    let originalBytes = try source.data(from: NSRange(location: 0, length: source.length),
                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    try originalBytes.write(to: external)
    controller.setEditing(true)
    controller.add(external)
    let externalPanel = try controller.views.values.first(where: { $0.url == external }).unwrap("Missing external file panel")
    let reader = try (externalPanel.subviews.compactMap { $0 as? NativeTextPanel }.first?.documentView as? PanelTextView).unwrap("Missing RTF reader")
    let hint = try externalPanel.subviews.compactMap { $0 as? PanelEditHint }.first.unwrap("Missing external file menu")
    try check(hint.accessibilityPerformPress(), "The external file menu must open in edit mode")
    let menu = try externalPanel.currentMenu.unwrap("Missing external file menu face")
    let duplicateAction = try menu.actions.first(where: { $0.title == "メモとして複製" }).unwrap("Missing editable copy action")
    MainActor.assumeIsolated { menu.choose(duplicateAction.tag) }
    let copy = try controller.records.last.flatMap { controller.views[$0.id] }.unwrap("Missing editable copy")
    let editableCopy = try noteView(copy)
    try check(copy.url != external && editableCopy.editor.string == "外部ファイルの本文" && editableCopy.editor.isEditable,
              "Copying an external file must open a managed note")
    var opened: [URL] = []
    for view in [reader, editableCopy.editor] {
        let link = try view.attributedString().attribute(.link, at: 0, effectiveRange: nil).unwrap("The RTF link must survive copying")
        view.openWebLink = { opened.append($0) }
        view.clicked(onLink: link, at: 0)
    }
    try check(opened == [linkURL, linkURL], "Both read-only and editable text must route their link through the browser opener")
    let restoredFile = copy.url.deletingLastPathComponent().appendingPathComponent("original.rtf")
    try FileManager.default.moveItem(at: copy.url, to: restoredFile)
    try FileManager.default.createDirectory(at: copy.url, withIntermediateDirectories: false)
    type("追記", in: editableCopy.editor)
    try check(!controller.notes.saveAll() && editableCopy.note.saveError != nil, "A failed atomic save must retain the pending document")
    try FileManager.default.removeItem(at: copy.url)
    try FileManager.default.moveItem(at: restoredFile, to: copy.url)
    let retry = try editableCopy.subviews.compactMap { $0 as? NSButton }.first(where: { $0.action == NSSelectorFromString("retrySave") }).unwrap("Missing save retry")
    try check(!retry.isHidden, "Save failure must expose a retry action")
    retry.performClick(nil)
    let recovered = try PanelDocumentStorage.readText(at: copy.url)
    let externalBytes = try Data(contentsOf: external)
    try check(retry.isHidden && recovered.string == editableCopy.editor.string && externalBytes == originalBytes,
              "Retry must save the pending edit and preserve the external file")
    print("PASS: inline note creation, lists and Return, character styles, undo/redo, autosave and retry, duplicate editors, legacy notes and external file copies")
}

func verifyContentPanels() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Scrim-Content-"+UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    try verifyNoteEditing(in: temp.appendingPathComponent("notes", isDirectory: true))
    let documents = PanelDocumentStorage(directory: temp.appendingPathComponent("managed", isDirectory: true))
    let controller = OverlayController(store: SettingsStore(storage: MemorySettingsStorage()), websiteDataStore: .nonPersistent(), documentStorage: documents)
    controller.show(.pinned); controller.setEditing(true)
    defer { controller.show(.hidden, immediately: true) }
    let contents = "日本語のメモ\n<b>HTML として実行しない</b>"
    let textURL = try documents.create(contents, kind: .text)
    controller.add(textURL)
    guard let text = controller.views.values.first else { throw CheckError.failed("Missing text panel") }
    text.layoutSubtreeIfNeeded()
    func textView(_ panel: PanelView) -> NSTextView? {
        panel.subviews.compactMap { $0 as? NativeNotePanel }.first?.editor ??
            (panel.subviews.compactMap { $0 as? NativeTextPanel }.first?.documentView as? NSTextView)
    }
    try check(textView(text)?.string == contents && textView(text)?.isEditable == false, "Layout editing must lock the note and display its literal text")
    try check(text.canEditContent, "Managed contents must expose edit action")
    let updated = "更新したメモ"
    try documents.replace(updated, at: textURL); text.reloadContent()
    try check(textView(text)?.string == updated, "Edited text must reload")
    text.sleep(); text.wake()
    try check(textView(text)?.string == updated, "Text must survive sleep and wake")
    try check(!text.subviews.contains { $0 is FilePanelErrorView }, "A readable file must not allocate an error view")
    try FileManager.default.removeItem(at: textURL)
    text.reloadContent()
    let errorView = try text.subviews.compactMap { $0 as? FilePanelErrorView }.first.unwrap("Missing file error view")
    try check(!errorView.isHidden && text.fileState.failureReason == .missing, "A missing file must show the existing error")
    try documents.replace(updated, at: textURL)
    text.reloadContent()
    try check(errorView.isHidden && textView(text)?.string == updated, "Reloading a restored file must dismiss the error")
    let utf16 = temp.appendingPathComponent("unicode.txt")
    try "UTF-16 のテキスト".write(to: utf16, atomically: true, encoding: .utf16)
    controller.add(utf16)
    guard let external = controller.views.values.first(where: { $0.url == utf16 }) else { throw CheckError.failed("Missing external text") }
    try check(textView(external)?.string == "UTF-16 のテキスト" && textView(external)?.isEditable == false && !external.canEditContent, "External text must decode without exposing managed editing")
    do {
        try documents.replace("unexpected", at: utf16)
        throw CheckError.failed("Managed editor must not write external files")
    } catch is CocoaError {}
    let htmlURL = try documents.create("<!doctype html><meta charset='utf-8'><h1>HTML fixture</h1>", kind: .html)
    try check(textURL.deletingLastPathComponent() != htmlURL.deletingLastPathComponent(), "HTML file-access directory must be isolated per document")
    controller.add(htmlURL)
    guard let html = controller.views.values.first(where: { $0.url == htmlURL }), let web = html.web else { throw CheckError.failed("Missing HTML view") }
    try waitFor("HTML rendering") { web.url?.isFileURL == true && !web.isLoading }
    let rendered = try javascript("document.body.innerText", in: web) as? String ?? ""
    try check(rendered.contains("HTML fixture"), "HTML must render as a document")
    text.command?(3)
    try check(FileManager.default.fileExists(atPath: textURL.path), "Closing a panel must preserve its saved content")
    let source = temp.appendingPathComponent("site", isDirectory: true)
    try FileManager.default.createDirectory(at: source.appendingPathComponent("pages"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: source.appendingPathComponent("assets"), withIntermediateDirectories: true)
    let entry = source.appendingPathComponent("pages/start.html")
    let reference = URL(string: "https://app.slack.com/client/T123/C456?thread_ts=1234567890.123456#detail")!
    try """
        <!doctype html><meta charset='utf-8'><link rel='stylesheet' href='../assets/style.css'>
        <h1>Embedded file</h1><img src='../assets/logo.svg'><script src='../assets/app.js'></script>
        <a id='reference' href='\(reference.absoluteString)'>Reference</a><a id='next' href='next.html'>Next</a>
        """.write(to: entry, atomically: true, encoding: .utf8)
    try "<title>Next page</title>".write(to: entry.deletingLastPathComponent().appendingPathComponent("next.html"), atomically: true, encoding: .utf8)
    try "h1 { color: rgb(12, 34, 56); }".write(to: source.appendingPathComponent("assets/style.css"), atomically: true, encoding: .utf8)
    try "window.importedScript = 'working';".write(to: source.appendingPathComponent("assets/app.js"), atomically: true, encoding: .utf8)
    try "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'><rect width='24' height='24' fill='blue'/></svg>".write(to: source.appendingPathComponent("assets/logo.svg"), atomically: true, encoding: .utf8)
    let imported = try documents.importHTML(entry, resourceRoot: source)
    try check(FileManager.default.fileExists(atPath: imported.path), "Imported entry file must exist: \(imported.path)")
    try FileManager.default.removeItem(at: source)
    controller.add(imported)
    let embedded = try controller.views.values.first(where: { $0.url == imported }).unwrap("Missing imported panel")
    let embeddedWeb = try embedded.web.unwrap("Missing imported WebKit view: \(embedded.fileState.source)")
    try waitFor("Imported HTML after source removal") { embeddedWeb.url?.isFileURL == true && !embeddedWeb.isLoading }
    let style = try javascript("getComputedStyle(document.querySelector('h1')).color", in: embeddedWeb) as? String
    let script = try javascript("window.importedScript", in: embeddedWeb) as? String
    let image = try javascript("document.querySelector('img').naturalWidth", in: embeddedWeb) as? Int
    try check(style == "rgb(12, 34, 56)" && script == "working" && image == 24, "Imported HTML must retain nested relative images/CSS/JS after deleting source")
    let root = try documents.resourceRoot(for: imported).unwrap("Missing imported resource root")
    try check(root != imported.deletingLastPathComponent(), "Nested entry must use its isolated package root")
    var opened: [URL] = []
    embedded.browser.openWebLink = { opened.append($0) }
    _ = try javascript("document.getElementById('reference').click()", in: embeddedWeb)
    try waitFor("Web link from local HTML") { !opened.isEmpty }
    try check(opened == [reference] && embeddedWeb.url == imported, "A Slack link in HTML must keep its HTTPS URL")
    _ = try javascript("document.getElementById('next').click()", in: embeddedWeb)
    try waitFor("relative HTML link") { embeddedWeb.url?.lastPathComponent == "next.html" && !embeddedWeb.isLoading }

    let pdfURL = temp.appendingPathComponent("links.pdf")
    let pdf = PDFDocument(), page = PDFPage()
    let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 100, height: 20), forType: .link, withProperties: nil)
    annotation.url = reference
    page.addAnnotation(annotation)
    pdf.insert(page, at: 0)
    try check(pdf.write(to: pdfURL), "Could not write PDF link fixture")
    controller.add(pdfURL)
    let pdfPanel = try controller.views.values.first(where: { $0.url == pdfURL }).unwrap("Missing PDF panel")
    pdfPanel.browser.openWebLink = { opened.append($0) }
    let pdfView = try pdfPanel.subviews.compactMap { $0 as? PDFView }.first.unwrap("Missing PDF view")
    let action = try (pdfView.document?.page(at: 0)?.annotations.first?.action).unwrap("Missing PDF link action")
    pdfView.perform(action)
    try check(opened == [reference, reference], "PDFKit must send the link to the same browser opener exactly once")
    print("PASS: managed text/HTML creation, literal native text, Unicode decoding, edit/reload, sleep/wake, external-write guard, per-document HTML scope, close preserves file")
    print("PASS: HTML folder import, nested entry, relative images/CSS/JS and pages, original source removal, HTML and PDF web links")
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw CheckError.failed(message) }; return value
    }
}

private struct FixtureWeather: WeatherProviding {
    let snapshot: WeatherSnapshot
    var fails = false
    func cached() async -> WeatherSnapshot? { snapshot }
    func hourlyForecast(force: Bool) async throws -> [WeatherHour] {
        if fails { throw URLError(.notConnectedToInternet) }
        return (1...8).map { hour -> WeatherHour in
            let date = Date().addingTimeInterval(Double(hour) * 10800)
            let temperature = Double(14 + hour)
            let probability = hour * 10
            let code = hour % 2 == 0 ? 2 : 61
            return WeatherHour(date: date, temperature: temperature,
                               precipitationProbability: probability, code: code)
        }
    }
    func fetch(force: Bool) async throws -> WeatherSnapshot {
        if fails { throw URLError(.notConnectedToInternet) }; return snapshot
    }
}

@MainActor func verifyWidgets(forecast: URL) async throws {
    try check(EventExclusion.matches(title: "Design Review", keywords: ["review"]), "Exclusion must ignore English letter case")
    try check(EventExclusion.matches(title: "来週の定例会議", keywords: ["定例"]), "Exclusion must match title substrings")
    try check(!EventExclusion.matches(title: "予定", keywords: ["", "  "]), "Blank keywords must never hide all events")
    try check(!EventExclusion.matches(title: "ガイド", keywords: ["カイド"]), "Voiced Japanese characters must remain distinct")
    try check(!EventExclusion.matches(title: "review", keywords: ["re.*"]), "Keywords must be literal, not regular expressions")
    let exclusionSpec = WidgetSpec(kind: .upcoming, calendarIDs: ["work"], agendaDays: 14, excludedKeywords: [" 定例 ", "Review", "review", "A&B + #"])
    try check(exclusionSpec.excludedKeywords == ["定例", "Review", "A&B + #"] && WidgetSpec(url: exclusionSpec.url) == exclusionSpec,
              "Keywords must normalize and persist alongside account and day settings")
    let iso = ISO8601DateFormatter()
    let london = WorkCity(id: "Europe/London")
    let sf = WorkCity(id: "America/Los_Angeles")
    let beforeDST = iso.date(from: "2026-03-06T16:00:00Z")!
    let afterDST = iso.date(from: "2026-03-09T16:00:00Z")!
    try check(sf.workingSlots([beforeDST, afterDST]) == [false, true] && london.workingSlots([afterDST]) == [true], "US and UK daylight-saving rules must be independent")
    let overnight = WorkCity(id: "Asia/Tokyo", start: 22, end: 6)
    let nightShifts = ["2026-03-06T17:00:00Z", "2026-03-08T17:00:00Z"].map { iso.date(from: $0)! }
    try check(overnight.workingSlots(nightShifts) == [true, false], "Night shifts must use the weekday on which the shift starts")
    func calculate(_ keys: [String]) -> String {
        var calculator = BasicCalculator()
        for key in keys { calculator.press(key) }
        return calculator.display
    }
    try check(calculate(["2","+","3","×","4","="]) == "14" && calculate(["2","+","3","=","="]) == "8", "Basic calculator precedence and repeated equals")
    try check(calculate(["2","0","0","+","1","0","%","="]) == "220" && calculate(["2","÷","0","="]) == "エラー", "Calculator percent and division by zero")
    let urgencyNow = Date()
    func timedEvent(_ seconds: TimeInterval, allDay: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: "timing", title: "予定", start: urgencyNow.addingTimeInterval(seconds), end: urgencyNow.addingTimeInterval(seconds + 3600), allDay: allDay, location: nil, color: .systemBlue, attendance: .accepted)
    }
    try check(AgendaPresentation.minutesUntilStart(timedEvent(3600), now: urgencyNow) == nil, "Exactly one hour must not trigger the under-hour highlight")
    try check(AgendaPresentation.minutesUntilStart(timedEvent(1800), now: urgencyNow) == 30, "Upcoming event must show minutes until start")
    try check(AgendaPresentation.minutesUntilStart(timedEvent(-60), now: urgencyNow) == nil && AgendaPresentation.minutesUntilStart(timedEvent(60, allDay: true), now: urgencyNow) == nil,
              "Ongoing and all-day events must not get upcoming urgency badges")
    let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
    var laterMeeting = timedEvent(600)
    laterMeeting.meetingURL = meet
    let hiddenUntil = [laterMeeting.id: laterMeeting.end.timeIntervalSince1970]
    try check(MeetingNotchBadge.isHidden(laterMeeting, occurrences: hiddenUntil, now: urgencyNow) &&
              !MeetingNotchBadge.isHidden(laterMeeting, occurrences: hiddenUntil, now: laterMeeting.end),
              "An occurrence must become eligible again at its stored expiry")
    func badge(_ events: [UpcomingEvent], limit: Int = 3, online: Bool = false) -> UpcomingEvent? {
        MeetingNotchBadge.candidate(events, now: urgencyNow, lead: 10, limit: limit, onlineOnly: online)
    }
    for status in AgendaAttendance.allCases where status != .accepted {
        var unconfirmed = timedEvent(0)
        unconfirmed.attendance = status
        try check(badge([unconfirmed, laterMeeting])?.start == laterMeeting.start, "Unaccepted ongoing events must not mask the accepted meeting")
    }
    try check(badge([laterMeeting], online: true) != nil && badge([timedEvent(601)]) == nil, "Badge must respect the exact lead boundary")
    try check(badge([laterMeeting, timedEvent(0)])?.start == urgencyNow, "A meeting starting now takes priority")
    try check(badge([timedEvent(-3600), timedEvent(0, allDay: true)]) == nil && badge([laterMeeting], limit: 1) == nil, "Ended, all-day, and exact-limit events must be excluded")
    try check(badge([timedEvent(0)], online: true) == nil, "Conference-link filter must apply to ongoing events")
    let offline = timedEvent(60)
    var unconfirmedMeeting = laterMeeting
    unconfirmedMeeting.attendance = .tentative
    try check(AgendaPresentation.nextAcceptedEvent([laterMeeting, offline, timedEvent(-60), timedEvent(5, allDay: true)], now: urgencyNow)?.start == offline.start,
              "The next accepted timed event must include offline events and skip all-day and ongoing events")
    try check(AgendaPresentation.nextAcceptedEvent([unconfirmedMeeting], now: urgencyNow) == nil, "An unaccepted meeting link must not qualify for the countdown")
    try check(AgendaPresentation.currentEvent([timedEvent(600), timedEvent(-60)], now: urgencyNow)?.start == urgencyNow.addingTimeInterval(-60),
              "Current-time navigation must prefer ongoing events")
    try check(AgendaPresentation.currentEvent([timedEvent(600), timedEvent(-7200)], now: urgencyNow)?.start == urgencyNow.addingTimeInterval(600),
              "Current-time navigation must skip ended events")
    let ordered = AgendaPresentation.groups([timedEvent(600), timedEvent(-7200), timedEvent(-60)], now: urgencyNow).flatMap(\.events)
    try check(ordered.map(\.start) == ordered.map(\.start).sorted(), "Ended events must remain in chronological order")
    try check(AgendaPresentation.countdown(to: urgencyNow.addingTimeInterval(61), now: urgencyNow) == "あと2分" &&
              AgendaPresentation.countdown(to: urgencyNow.addingTimeInterval(3660), now: urgencyNow) == "あと1時間1分",
              "Meeting countdown must round up minutes and format hours")
    let zoom = URL(string: "https://example.zoom.us/j/123456789?pwd=synthetic")!
    let notion = URL(string: "https://www.notion.so/synthetic-agenda")!
    let links = EventLinks.extract(in: [meet.absoluteString, "<a href=\"\(notion.absoluteString)\">議事録</a><br>検討事項 &amp; 次の作業", zoom.absoluteString, meet.absoluteString])
    try check(links.count == 3 && links.filter { $0.meetingService != nil }.count == 2, "Multiple meeting and reference links must be extracted without duplicates")
    try check(links.first(where: { $0.url == notion })?.title == "議事録" && links.first(where: { $0.url == notion })?.isNotion == true, "Notion links must retain anchor labels and service identity")
    try check(EventLinks.notes("<p>検討事項 &amp; 次の作業</p>\(meet.absoluteString)") == "検討事項 & 次の作業", "Notes must be inert text without duplicate web URLs")
    try check(!EventLinks.isWebURL(URL(string: "file:///tmp/agenda")!) && !EventLinks.isWebURL(URL(string: "https://user:password@example.invalid")!), "Reference links must reject local files and embedded credentials")
    try check(MeetingLink.find(in: [nil, "会議室", "参加はこちら: \(meet.absoluteString)"]) == meet, "Meeting links in notes must be found")
    try check(MeetingLink.find(in: [zoom.absoluteString, nil]) == zoom, "Zoom URL and query must be preserved")
    try check(MeetingLink.find(in: ["meet.google.com/abc-defg-hij"]) == meet, "Bare meeting links must open securely with HTTPS")
    try check(MeetingLink.find(in: ["https://zoom.us.evil.invalid/j/123", "https://example.invalid/?url=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij"]) == nil,
              "Unrelated and lookalike domains must not become meeting buttons")
    let dayStart = Calendar.current.startOfDay(for: Date())
    let dayEvents = [
        UpcomingEvent(id: "past", title: "朝の予定", start: dayStart.addingTimeInterval(1), end: dayStart.addingTimeInterval(2), allDay: false, location: "会議室", color: .systemBlue),
        UpcomingEvent(id: "tomorrow", title: "明日の予定", start: Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(3600), end: Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(7200), allDay: false, location: "オンライン", color: .systemGreen)
    ]
    let rangeModel = UpcomingEventsModel(previewEvents: dayEvents)
    var openedReference: URL?
    rangeModel.onOpenLink = { openedReference = $0 }
    rangeModel.openLink(notion)
    try check(openedReference == notion, "Reference buttons must route to the external opener")
    openedReference = nil
    rangeModel.openLink(URL(string: "file:///tmp/agenda")!)
    try check(openedReference == nil, "Unsafe URLs must never reach the external opener")
    rangeModel.setDisplayDays(1)
    try check(rangeModel.events.map(\.id) == ["past"], "One-day range must include today's finished events and exclude tomorrow")
    rangeModel.setDisplayDays(2)
    try check(rangeModel.events.count == 2, "Two-day range must include tomorrow")
    let groups = AgendaPresentation.groups(rangeModel.events, now: Date())
    try check(groups.count == 2 && groups.first?.date == dayStart, "Events must be grouped into today then tomorrow")
    let dateSpec = WidgetSpec(kind: .upcoming, calendarIDs: ["chosen"], agendaDays: 14)
    try check(WidgetSpec(url: dateSpec.url) == dateSpec, "Day range and calendar selection must survive together")
    let hourlyData = Data(#"{"weather":[{"date":"2026-11-17","hourly":[{"time":"0","tempC":"11","weatherCode":"113","chanceofrain":"0"},{"time":"100","tempC":"12","weatherCode":"116","chanceofrain":"20"},{"time":"300","tempC":"13","weatherCode":"296","chanceofrain":"60"}]}]}"#.utf8)
    let parsedHours = try ThreeHourlyWeather.parse(hourlyData)
    try check(parsedHours.count == 2 && parsedHours.last?.temperature == 13 && parsedHours.last?.precipitationProbability == 60,
              "Hourly forecast must retain actual three-hour slots and probabilities")
    let liveHourlyFixture = URL(fileURLWithPath: ".tmp/hourly-wttr.json")
    if FileManager.default.fileExists(atPath: liveHourlyFixture.path) {
        let liveHours = try ThreeHourlyWeather.parse(Data(contentsOf: liveHourlyFixture))
        try check(liveHours.count >= 8, "Live Tokyo forecast response must contain three-hour weather data")
    }
    let options = [
        CalendarOption(id: "work/primary?x=1&y=2", title: "会議", accountID: "work", accountTitle: "仕事", color: .systemBlue),
        CalendarOption(id: "work/team", title: "チーム", accountID: "work", accountTitle: "仕事", color: .systemOrange),
        CalendarOption(id: "personal", title: "プライベート", accountID: "home", accountTitle: "個人用", color: .systemRed)
    ]
    let fakeEvents = options.enumerated().map { index, option in
        UpcomingEvent(id: option.id, title: option.title, start: Date(), end: Date().addingTimeInterval(3600),
                      allDay: false, location: nil, color: option.color, calendarID: option.id)
    }
    let filtered = UpcomingEventsModel(previewEvents: fakeEvents, previewCalendars: options)
    var openedMeeting: URL?
    filtered.onOpenMeeting = { openedMeeting = $0 }
    filtered.openMeeting(meet)
    try check(openedMeeting == meet, "Meeting button must route the original URL to the external opener")
    openedMeeting = nil
    filtered.openMeeting(URL(string: "https://example.invalid/")!)
    try check(openedMeeting == nil, "Non-meeting URLs must not use the meeting opener")
    filtered.setSelected(["personal"], enabled: false)
    try check(Set(filtered.events.map(\.calendarID)) == Set(options.prefix(2).map(\.id)), "Disabling an account must remove its events")
    filtered.setSelected([options[0].id], enabled: false)
    try check(filtered.events.map(\.calendarID) == ["work/team"], "Individual calendars must be independently selectable")
    filtered.select([])
    try check(filtered.events.isEmpty, "Deselecting all calendars must never fall back to all events")
    let emptyURL = WidgetSpec(kind: .upcoming, calendarIDs: []).url
    try check(WidgetSpec(url: emptyURL)?.calendarIDs == Set<String>(), "Explicit empty selection must survive reload")
    let chosen = Set([options[0].id])
    let selectionURL = WidgetSpec(kind: .upcoming, calendarIDs: chosen).url
    try check(WidgetSpec(url: selectionURL)?.calendarIDs == chosen, "Calendar IDs with URL characters must round-trip")
    let restored = UpcomingEventsModel(selectedCalendarIDs: WidgetSpec(url: selectionURL)!.calendarIDs,
                                       previewEvents: fakeEvents, previewCalendars: options)
    try check(restored.events.map(\.calendarID) == [options[0].id], "Reloaded selection must exclude other accounts")
    filtered.select(nil)
    let excludeID = filtered.addExcludedKeyword()
    filtered.editExcludedKeyword(excludeID, text: "会議")
    try check(filtered.events.count == 2 && !filtered.events.contains(where: { $0.title == "会議" }), "Adding a keyword must immediately exclude matching events")
    let secondExcludeID = filtered.addExcludedKeyword()
    filtered.editExcludedKeyword(secondExcludeID, text: "チーム")
    try check(filtered.events.map(\.title) == ["プライベート"], "Multiple keywords must apply as OR filters")
    filtered.editExcludedKeyword(excludeID, text: "プライベート")
    try check(filtered.events.map(\.title) == ["会議"], "Editing a keyword must restore old matches and hide new matches")
    filtered.removeExcludedKeyword(secondExcludeID)
    try check(filtered.events.count == 2, "Deleting a keyword must restore its events")
    filtered.removeExcludedKeyword(excludeID)
    try check(filtered.events.count == 3, "Select all must restore every available calendar")
    let reference = CGSize(width: 2560, height: 1440)
    let placements = [CGRect(x: 440, y: 1080, width: 400, height: 330),
                      CGRect(x: 860, y: 1080, width: 400, height: 330),
                      CGRect(x: 440, y: 28, width: 1030, height: 1030),
                      CGRect(x: 28, y: 28, width: 400, height: 1380)]
    let shared = DisplayLayout(panels: placements.map {
        PanelRecord(url: WidgetSpec(kind: .clock).url, placement: FractionalFrame(frame: $0, screen: reference))
    }, referenceSize: reference)
    for screen in [reference, CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080)] {
        let frames = LayoutFitter.relativeFrames(layout: shared, screen: screen)
        for (record, frame) in zip(shared.panels, frames) {
            try check(abs(frame.minX / screen.width - record.placement.x) < 0.00001 &&
                      abs(frame.minY / screen.height - record.placement.y) < 0.00001 &&
                      abs(frame.width / screen.width - record.placement.width) < 0.00001 &&
                      abs(frame.height / screen.height - record.placement.height) < 0.00001,
                      "Shared layout must preserve relative geometry across screen sizes")
        }
        var reordered = shared; reordered.panels.reverse()
        try check(LayoutFitter.relativeFrames(layout: reordered, screen: screen) == Array(frames.reversed()),
                  "Bringing a panel forward must not repack shared geometry")
    }
    let data = try Data(contentsOf: forecast)
    let snapshot = try JMAWeather.parseForecast(data)
    try check(snapshot.city == "東京" && snapshot.days.count >= 3, "Tokyo forecast must parse")
    try check(snapshot.temperature == nil, "Forecast temperatures must not masquerade as current observation")
    let observation = Data("{\"20261117111000\":{\"temp\":[11.5,0]},\"20261117112000\":{\"temp\":[99,1]}}".utf8)
    let observed = try JMAWeather.observation(observation)
    try check(observed?.0 == 11.5, "Bad-quality observations must be skipped")
    try check(JMAWeather.observationURL(latestTime: "2026-11-17T11:20:00+09:00")?.lastPathComponent == "20261117_09.json", "Observation block must follow Tokyo time")
    let store = SettingsStore(storage: MemorySettingsStorage())
    try check(store.agendaResetsScrollOnOpen, "Agenda scroll must reset on reopen by default")
    store.agendaResetsScrollOnOpen = false
    try check(!store.agendaResetsScrollOnOpen, "Agenda scroll reset switch must persist off")
    store.agendaResetsScrollOnOpen = true
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent(), weatherProvider: FixtureWeather(snapshot: snapshot))
    controller.show(.pinned); controller.setEditing(true)
    defer { controller.show(.hidden, immediately: true) }
    for kind in WidgetKind.allCases { controller.add(WidgetSpec(kind: kind).url) }
    try check(controller.records.count == WidgetKind.allCases.count && controller.pool.entries.isEmpty, "Native widgets must not consume WebView slots")
    if let smallClock = controller.views.values.first(where: { WidgetSpec(url: $0.url)?.kind == .clock }) {
        let original = smallClock.frame
        let scaled = CGRect(x: 300, y: 700, width: 285, height: 126)
        smallClock.frame = scaled
        controller.setEditing(false)
        controller.setEditing(true)
        try check(smallClock.frame == scaled, "Editing must not enlarge or re-snap a scaled clock on the smaller display")
        smallClock.frame = original
    }
    let frames = controller.views.values.map(\.frame)
    for i in frames.indices { for j in frames.indices where j > i { try check(!frames[i].intersects(frames[j]), "New widgets must not overlap when space is available") } }
    let widgets = controller.views.values.compactMap { $0.subviews.compactMap { $0 as? NativeWidgetPanel }.first }
    try check(widgets.count == WidgetKind.allCases.count && widgets.allSatisfy { $0.model.active }, "Widgets must be active while shown")
    let agenda = try widgets.first(where: { $0.model.spec.kind == .upcoming }).unwrap("Missing agenda widget")
    let agendaModel = try agenda.model.upcoming.unwrap("Missing agenda event model")
    try check(widgets.compactMap { $0.model.upcoming }.count == 1, "Only the agenda widget needs a calendar event store")
    try check(agenda.model.isEditing, "Agenda settings button must appear while editing")
    let presentation = agendaModel.presentationRevision
    controller.show(.hidden, immediately: true)
    controller.show(.peek, immediately: true)
    try check(agendaModel.presentationRevision == presentation + 1, "Reopening must reset agenda scroll when enabled")
    controller.show(.pinned, immediately: true)
    try check(agendaModel.presentationRevision == presentation + 1, "Pinning a visible peek must preserve scroll")
    store.agendaResetsScrollOnOpen = false
    controller.show(.hidden, immediately: true)
    controller.show(.pinned, immediately: true)
    try check(agendaModel.presentationRevision == presentation + 1, "Disabled reset must preserve scroll on reopen")
    controller.setEditing(true)
    agendaModel.select([options[0].id])
    agendaModel.setDisplayDays(14)
    let persistedKeyword = agendaModel.addExcludedKeyword()
    agendaModel.editExcludedKeyword(persistedKeyword, text: "除外する予定")
    let agendaRecord = try store.panels.first(where: { WidgetSpec(url: $0.url)?.kind == .upcoming }).unwrap("Missing saved agenda")
    try check(WidgetSpec(url: agendaRecord.url)?.calendarIDs == chosen && WidgetSpec(url: agendaRecord.url)?.agendaDays == 14 && WidgetSpec(url: agendaRecord.url)?.excludedKeywords == ["除外する予定"], "Calendar filter, day count and keywords must persist together on the panel")
    let agendaPanel = try (agenda.superview as? PanelView).unwrap("Missing agenda panel")
    agendaPanel.showSettings()
    try check(controller.panelWithSettings === agendaPanel, "Agenda settings must open in the centered overlay")
    controller.setEditing(false)
    try check(controller.panelWithSettings == nil && !agenda.model.isEditing, "Leaving edit mode must close agenda settings")
    controller.setEditing(true)
    let weather = try widgets.first(where: { $0.model.spec.kind == .weather }).unwrap("Missing weather widget")
    let deadline = Date().addingTimeInterval(5)
    while weather.model.weather == nil || weather.model.loading {
        guard Date() < deadline else { throw CheckError.failed("Widget weather task did not finish") }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try check(weather.model.weather?.city == "東京", "Weather must update from its provider")
    let clock = try controller.views.values.first(where: { WidgetSpec(url: $0.url)?.kind == .clock }).unwrap("Missing clock panel")
    let clockHost = try clock.subviews.compactMap { $0 as? NativeWidgetPanel }.first.unwrap("Missing clock host")
    controller.setEditing(false)
    clock.performMenuAction(21)
    try check(clockHost.model.clockStyle == .analog, "Clock menu changes must require edit mode")
    controller.setEditing(true)
    clock.performMenuAction(21)
    let savedClock = try store.panels.first(where: { $0.id == clock.id }).unwrap("Clock must remain saved")
    try check(WidgetSpec(url: savedClock.url)?.clockStyle == .digital, "Clock selection must persist per panel")
    let restoredClock = WidgetModel(spec: WidgetSpec(url: savedClock.url)!)
    try check(restoredClock.clockStyle == .digital, "Recreated clock must restore digital style")
    clock.command?(3)
    try check(!clockHost.model.active, "Closing a widget must stop its updates immediately")
    controller.show(.hidden, immediately: true)
    try check(widgets.allSatisfy { !$0.model.active }, "Hiding must stop widget updates")
    try check(store.panels.allSatisfy { WidgetSpec(url: $0.url) != nil }, "Widget descriptors must persist")
    let failing = WidgetModel(spec: WidgetSpec(kind: .weather), provider: FixtureWeather(snapshot: snapshot, fails: true))
    failing.setActive(true)
    let errorDeadline = Date().addingTimeInterval(5)
    while failing.loading {
        guard Date() < errorDeadline else { throw CheckError.failed("Failure state did not settle") }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try check(failing.weather != nil && failing.error != nil, "Offline state must retain cached weather and expose failure")
    failing.setActive(false)
    let sampleTitles = ["デザインレビュー", "チーム定例", "プロジェクト打ち合わせ", "開発の進捗確認"]
    var sampleEvents: [UpcomingEvent] = []
    for index in 0..<12 {
        let start = Date().addingTimeInterval(index == 0 ? 600 : Double(index + 1) * 3600)
        let color: NSColor = index % 2 == 0 ? .systemOrange : .systemBlue
        let event = UpcomingEvent(id: "sample-\(index)", title: sampleTitles[index % 4], start: start,
                                  end: start.addingTimeInterval(1800), allDay: false,
                                  location: index % 3 == 0 ? "会議室" : nil, color: color, attendance: .accepted,
                                  meetingURL: index % 3 == 0 ? URL(string: "https://meet.google.com/abc-defg-hij") : index % 3 == 1 ? URL(string: "https://example.zoom.us/j/123456789") : nil,
                                  links: [EventLink(url: notion, title: "議事録とアジェンダ")], notes: "確認事項をまとめておきましょう。")
        sampleEvents.append(event)
    }
    let preview = UpcomingEventsModel(previewEvents: sampleEvents)
    let review = NSHostingView(rootView: UpcomingEventsView(model: preview, now: Date(), size: CGSize(width: 620, height: 335)))
    review.frame = NSRect(x: 0, y: 0, width: 620, height: 335)
    let reviewWindow = NSWindow(contentRect: review.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    reviewWindow.contentView = review
    reviewWindow.orderFront(nil)
    review.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
    let agendaScroll = try scrollView(in: review).unwrap("Agenda must expose a native vertical scroll view")
    try check(agendaScroll.scrollerStyle == .overlay && agendaScroll.autohidesScrollers && agendaScroll.verticalScroller?.controlSize == .small, "Agenda must use a small autohiding overlay scrollbar")
    let top = agendaScroll.contentView.bounds.origin.y
    agendaScroll.contentView.scroll(to: NSPoint(x: 0, y: top + 160))
    agendaScroll.reflectScrolledClipView(agendaScroll.contentView)
    let scrolled = agendaScroll.contentView.bounds.origin.y
    try check(abs(scrolled - top) > 100, "Agenda fixture must actually scroll before testing reopen")
    preview.beginPresentation(resetScroll: false)
    try await Task.sleep(nanoseconds: 100_000_000)
    try check(abs(agendaScroll.contentView.bounds.origin.y - scrolled) < 1, "Disabled reset must retain the actual scroll position")
    preview.beginPresentation(resetScroll: true)
    try await Task.sleep(nanoseconds: 100_000_000)
    let currentPosition = agendaScroll.contentView.bounds.origin.y
    try check(abs(currentPosition - scrolled) > 2 && currentPosition >= top, "Enabled reset must move the actual rendered agenda to its current event")
    agendaScroll.contentView.scroll(to: NSPoint(x: 0, y: top))
    agendaScroll.reflectScrolledClipView(agendaScroll.contentView)
    if let bitmap = review.bitmapImageRepForCachingDisplay(in: review.bounds) {
        review.cacheDisplay(in: review.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/upcoming-review.png"))
    }
    review.rootView = UpcomingEventsView(model: preview, now: Date(), size: CGSize(width: 340, height: 650))
    reviewWindow.setContentSize(NSSize(width: 340, height: 650))
    review.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    if let bitmap = review.bitmapImageRepForCachingDisplay(in: review.bounds) {
        review.cacheDisplay(in: review.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/upcoming-countdown-review.png"))
    }
    reviewWindow.orderOut(nil)
    let reviewKeyword = filtered.addExcludedKeyword()
    filtered.editExcludedKeyword(reviewKeyword, text: "非表示にしたい予定")
    let back = NSHostingView(rootView: PanelSettingsSurface(title: "次の予定", close: {}) {
        UpcomingEventsSettings(model: filtered)
    })
    back.frame = NSRect(x: 0, y: 0, width: 640, height: 540)
    reviewWindow.setContentSize(NSSize(width: 640, height: 540))
    reviewWindow.contentView = back; reviewWindow.orderFront(nil); back.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    if let bitmap = back.bitmapImageRepForCachingDisplay(in: back.bounds) {
        back.cacheDisplay(in: back.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/upcoming-settings-review.png"))
    }
    reviewWindow.orderOut(nil)
    let isolatedCalendar = UpcomingEventsModel()
    isolatedCalendar.setActive(true)
    isolatedCalendar.requestAccess()
    try check(isolatedCalendar.events.isEmpty && !isolatedCalendar.requesting && isolatedCalendar.status == .notDetermined,
              "Verification must never read personal calendars or request calendar permission")
    for kind in [WidgetKind.weather, .clock, .calendar, .worldclock] {
        let model = WidgetModel(spec: WidgetSpec(kind: kind), provider: FixtureWeather(snapshot: snapshot))
        model.weather = snapshot
        if kind == .weather {
            model.setActive(true)
            let deadline = Date().addingTimeInterval(5)
            while model.hourly.isEmpty && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            try check(model.hourly.count == 8, "Weather must fetch its hourly forecast")
        }
        let host = NSHostingView(rootView: WidgetPanelView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 340)
        reviewWindow.contentView = host; reviewWindow.orderFront(nil); host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CheckError.failed("Widget did not render") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/" + kind.rawValue + "-review.png"))
        if kind == .weather {
            reviewWindow.setContentSize(NSSize(width: 620, height: 180)); host.frame = NSRect(x: 0, y: 0, width: 620, height: 180)
            host.layoutSubtreeIfNeeded()
            if let wide = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: wide)
                try wide.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/weather-wide-review.png"))
            }
            model.setShowsHourly(false)
            try check(!model.showsHourly, "Hourly forecast must be hideable")
        }
        model.setActive(false)
    }
    let digital = WidgetModel(spec: WidgetSpec(kind: .clock, clockStyle: .digital))
    let digitalHost = NSHostingView(rootView: WidgetPanelView(model: digital))
    digitalHost.frame = NSRect(x: 0, y: 0, width: 340, height: 340)
    reviewWindow.contentView = digitalHost; reviewWindow.orderFront(nil); digitalHost.layoutSubtreeIfNeeded()
    if let bitmap = digitalHost.bitmapImageRepForCachingDisplay(in: digitalHost.bounds) {
        digitalHost.cacheDisplay(in: digitalHost.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/clock-digital-review.png"))
    }
    reviewWindow.orderOut(nil)
    print("PASS: Tokyo parsing, observation quality/time, native widget rendering, non-overlap, WebView isolation, persistence, hidden update stop, cached offline state")
}

@MainActor func showWidgetsReview() -> OverlayController {
    let store = SettingsStore(storage: MemorySettingsStorage()); store.showsOverlayControls = true
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
    controller.show(.pinned); controller.setEditing(true)
    for kind in WidgetKind.allCases { controller.add(WidgetSpec(kind: kind).url) }
    controller.setEditing(false); controller.onDismiss = { NSApp.terminate(nil) }
    NSApp.activate(ignoringOtherApps: true)
    return controller
}

/// Visible QA uses only the local fixture and memory; the normal app setup is skipped.
func showInteractionReview(fixture: URL) -> OverlayController {
    let store = SettingsStore(storage: MemorySettingsStorage())
    store.showsOverlayControls = true
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
    controller.show(.pinned); controller.setEditing(true); controller.add(fixture); controller.setEditing(false)
    controller.onDismiss = { NSApp.terminate(nil) }
    NSApp.activate(ignoringOtherApps: true)
    return controller
}


@MainActor func verifyOverlayFades() async throws {
    let controller = OverlayController(store: SettingsStore(storage: MemorySettingsStorage()), websiteDataStore: .nonPersistent())
    defer { controller.show(.hidden, immediately: true) }
    controller.show(.peek)
    try await Task.sleep(nanoseconds: 100_000_000)
    let partial = controller.panel.alphaValue
    try check(partial > 0 && partial < 1, "Showing must fade through intermediate opacity")
    controller.show(.pinned)
    try await Task.sleep(nanoseconds: 220_000_000)
    try check(controller.panel.alphaValue > 0.99, "Pinning during fade-in must finish visible")
    controller.show(.hidden)
    try await Task.sleep(nanoseconds: 100_000_000)
    try check(controller.panel.alphaValue > 0 && controller.panel.alphaValue < 1, "Hiding must fade through intermediate opacity")
    controller.show(.peek)
    try await Task.sleep(nanoseconds: 350_000_000)
    try check(controller.panel.alphaValue > 0.99 && controller.state == .peek, "Reopening during fade-out must stay visible")
    controller.show(.hidden)
    try await Task.sleep(nanoseconds: 350_000_000)
    try check(controller.panel.alphaValue < 0.01 && controller.panel.ignoresMouseEvents, "Fade-out must finish transparent and pass clicks through")
    controller.show(.peek)
    try await Task.sleep(nanoseconds: 80_000_000)
    controller.show(.hidden, immediately: true)
    try await Task.sleep(nanoseconds: 350_000_000)
    try check(controller.panel.alphaValue < 0.01, "Emergency cancellation must override an in-flight fade")
    print("PASS: 0.25s fade-in/out, pin during fade-in, reverse during fade-out, click-through, immediate cancellation")
}


func verifyPanelBehavior() throws {
    let storage = MemorySettingsStorage()
    let store = SettingsStore(storage: storage)
    let transient = URL(string: "https://calendar.notion.com/auth?code=synthetic-only")!
    let canonical = URL(string: "https://calendar.notion.com/")!
    let id = UUID()
    let placement = FractionalFrame(frame: CGRect(x: 40, y: 40, width: 600, height: 500), screen: CGSize(width: 1512, height: 982))
    store.panels = [PanelRecord(id: id, url: transient, placement: placement)]
    store.normalizeWebLaunchURLs()
    try check(store.panels.first?.url == canonical && store.panels.first?.id == id && store.panels.first?.placement == placement,
              "Auth callbacks must be replaced without changing layout or identity")
    try check(WebPanelPolicy.savedURL(transient, previous: canonical) == canonical, "Login URLs must never replace calendar launch URL")
    try check(WebPanelPolicy.launchURL(URL(string: "https://calendar.notion.com/week/2020/1/1")!) == canonical,
              "Dated calendar URLs must not reopen old periods")
    store.panels = []
    try check(store.peekAllowsInteraction, "Peek interaction must default on")
    var machine = DoublePressMachine()
    _ = machine.update(GestureSnapshot(left: true), at: 0)
    _ = machine.update(GestureSnapshot(), at: 0.1)
    try check(machine.update(GestureSnapshot(left: true), at: 0.2) == .peek, "Double press must open peek")
    try check(machine.interrupt(key: false) == .none, "Mouse click must not cancel interactive peek")
    try check(machine.update(GestureSnapshot(left: true, mouseDown: true), at: 0.4) == .none, "Dragging must retain peek")
    try check(machine.update(GestureSnapshot(mouseDown: true), at: 0.8) == .hide, "Releasing Command must hide even during a drag")
    machine = DoublePressMachine(allowsPeekInteraction: false)
    _ = machine.update(GestureSnapshot(left: true), at: 0)
    _ = machine.update(GestureSnapshot(), at: 0.1)
    _ = machine.update(GestureSnapshot(left: true), at: 0.2)
    try check(machine.interrupt(key: false) == .hideImmediately, "Disabled peek interaction must retain click-through behavior")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scrim-pointer-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("index.html")
    try """
    <!doctype html><meta charset="utf-8"><style>body{margin:0;height:3000px}button{position:absolute;left:30px;top:30px;width:200px;height:60px}</style>
    <button id="click" onclick="document.body.dataset.clicked=String(event.metaKey)">クリックを確認</button>
    <script>window.todayCount=0;</script>
    """.write(to: file, atomically: true, encoding: .utf8)
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
    defer { controller.show(.hidden, immediately: true) }
    controller.show(.pinned, immediately: true); controller.setEditing(true); controller.add(file); controller.setEditing(false)
    let view = try controller.views.values.first.unwrap("Missing pointer panel")
    view.layoutSubtreeIfNeeded()
    let web = try view.web.unwrap("Missing pointer WebView")
    try waitFor("pointer fixture") { !web.isLoading && web.url?.isFileURL == true }
    defer { SettingsController.applyAppearance(.system) }
    for mode in [AppearanceMode.dark, .light] {
        SettingsController.applyAppearance(mode)
        try waitFor("live web appearance") {
            (try? javascript("matchMedia('(prefers-color-scheme: dark)').matches", in: web) as? Bool) == (mode == .dark)
        }
    }
    let scrollbar = try javascript("getComputedStyle(document.documentElement).scrollbarWidth", in: web) as? String
    try check(scrollbar == "thin", "Web scrollbar should be thin")

    controller.show(.peek, immediately: true)
    try check(!controller.panel.ignoresMouseEvents && !controller.editing, "Interactive peek must accept pointer events without editing")
    try check(web.acceptsFirstMouse(for: nil), "Web panel must accept the first click")
    controller.panel.setFrameOrigin(.zero)
    let local = NSPoint(x: 100, y: web.isFlipped ? 60 : web.bounds.height-60)
    let position = web.convert(local, to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = NSEvent.mouseEvent(with: type, location: position, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        let normalized = PanelPointerEvents.withoutCommand(event)
        try check(!normalized.modifierFlags.contains(.command) && normalized.windowNumber == event.windowNumber,
                  "Held Command must not turn panel clicks into Command-clicks")
        if type == .leftMouseDown { web.mouseDown(with: normalized) } else { web.mouseUp(with: normalized) }
    }
    try waitFor("native WebKit click") { (try? javascript("document.body.dataset.clicked", in: web) as? String) == "false" }
    store.peekAllowsInteraction = false
    controller.show(.peek, immediately: true)
    try check(controller.panel.ignoresMouseEvents, "Peek interaction preference must reach the actual window")
    store.peekAllowsInteraction = true
    controller.show(.pinned, immediately: true)
    let dialogSettings = SettingsController(store: store, permissionState: { false }, loginService: FakeLoginItemService())
    var openedSettings = false
    controller.onOpenSettings = { openedSettings = true; controller.presentSettings(dialogSettings) }
    let toolbar = try controller.root.subviews.compactMap { $0 as? OverlayControls }.first.unwrap("Missing overlay controls")
    func sendKey(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        NSApp.sendEvent(event)
    }
    func sendCommandComma() { sendKey(43, ",", modifiers: .command) }
    try check(toolbar.isHidden, "Pinned HUD must start hidden")
    sendCommandComma()
    try check(controller.showingActions && toolbar.isHidden, "Command-comma must open the centered action list")
    sendCommandComma()
    try check(!controller.showingActions, "Command-comma must dismiss the action list")
    sendCommandComma()
    sendKey(125, "\u{f701}")
    sendKey(36, "\r")
    try check(openedSettings && dialogSettings.embeddedWindow === controller.panel && !dialogSettings.window.isVisible,
              "Arrow and Return must open settings inside the overlay")
    controller.closeDialog()
    try check(dialogSettings.embeddedWindow == nil, "Closing settings must release the overlay presentation")
    do {
        final class QuitProbe: NSObject, NSApplicationDelegate {
            var requests = 0
            func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
                requests += 1
                return .terminateCancel
            }
        }
        let probe = QuitProbe()
        let previousDelegate = NSApp.delegate
        NSApp.delegate = probe
        defer { NSApp.delegate = previousDelegate }
        sendCommandComma()
        sendKey(126, "\u{f700}")
        sendKey(53, "\u{1b}")
        try check(probe.requests == 0 && !controller.showingActions, "Escape must dismiss the list without quitting")
        sendCommandComma()
        sendKey(125, "\u{f701}")
        sendKey(125, "\u{f701}")
        sendKey(36, "\r")
        try check(probe.requests == 1 && !controller.showingActions, "Choosing Quit must request normal application termination once")
    }
    _ = try javascript(CalendarWebNavigation.today, in: web)
    _ = try javascript("setTimeout(()=>{const b=document.createElement('button');b.textContent='Today';b.onclick=()=>{window.todayCount++;document.body.dataset.period='today'};document.body.append(b)},100)", in: web)
    try waitFor("asynchronous Today toolbar") { (try? javascript("window.todayCount", in: web) as? Int) == 1 }
    _ = try javascript("document.body.dataset.period='future';document.body.append(document.createElement('div'))", in: web)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let periodAfterBrowsing = try javascript("document.body.dataset.period", in: web) as? String
    try check(periodAfterBrowsing == "future", "Today reset must stop after one click and allow browsing other periods")
    _ = try javascript("document.querySelectorAll('button').forEach(b=>b.remove());window.todayCount=0", in: web)
    _ = try javascript(CalendarWebNavigation.today, in: web)
    _ = try javascript(CalendarWebNavigation.cancel, in: web)
    _ = try javascript("const b=document.createElement('button');b.textContent='今日';b.onclick=()=>window.todayCount++;document.body.append(b)", in: web)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let countAfterCancel = try javascript("window.todayCount", in: web) as? Int
    try check(countAfterCancel == 0, "Hidden calendar must cancel pending Today navigation")
    let preferences = SettingsController(store: store, permissionState: { true }, loginService: FakeLoginItemService())
    controller.show(.peek, immediately: true)
    try check(!controller.editing, "Long-hold peek must remain outside edit mode")
    preferences.setWebDisplayMode(.mobile)
    try check(SettingsStore(storage: storage).webDisplayMode == .mobile, "Mobile preference must persist")
    let mobileRecord = PanelRecord(url: URL(string: "https://example.invalid/")!, placement: placement)
    let mobileView = PanelView(record: mobileRecord, preview: true)
    let mobileWeb = PanelWebView(frame: .zero)
    mobileView.web = mobileWeb; mobileView.addSubview(mobileWeb)
    mobileView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    mobileView.setWebDisplayMode(.mobile); mobileView.layoutSubtreeIfNeeded()
    try check(mobileWeb.frame.width == 390 && mobileWeb.customUserAgent?.contains("iPhone") == true, "Mobile mode must use narrow viewport and mobile User-Agent")
    mobileView.setWebDisplayMode(.desktop); mobileView.layoutSubtreeIfNeeded()
    try check(mobileWeb.frame.width == 800 && (mobileWeb.customUserAgent ?? "").isEmpty, "Desktop mode must restore full viewport and standard User-Agent")
    try check(store.hideFromScreenCapture, "Capture exclusion must default on")
    controller.show(.pinned, immediately: true)
    try check(controller.panel.sharingType == .none, "Overlay must apply the Notch capture-exclusion request")
    preferences.setCaptureExclusion(false); controller.show(.pinned, immediately: true)
    try check(preferences.window.sharingType == .readOnly && controller.panel.sharingType == .readOnly,
              "Capture exclusion must be reversible for screenshots")
    controller.setEditing(true)
    let firstURL = URL(string: "https://first.invalid/")!
    let secondURL = URL(string: "https://second.invalid/")!
    controller.add(firstURL)
    controller.add(secondURL)
    let firstPanel = try controller.records.first(where: { $0.url == firstURL }).unwrap("Missing first web panel")
    let secondPanel = try controller.records.first(where: { $0.url == secondURL }).unwrap("Missing second web panel")
    let changedURL = URL(string: "https://updated.invalid/")!
    controller.updateWebPanel(firstPanel.id, url: changedURL, mode: .mobile)
    controller.show(.hidden, immediately: true)
    controller.show(.pinned, immediately: true)
    try check(controller.records.first(where: { $0.id == firstPanel.id })?.url == changedURL &&
              controller.records.first(where: { $0.id == firstPanel.id })?.webDisplayMode == .mobile &&
              controller.records.first(where: { $0.id == secondPanel.id })?.webDisplayMode == .desktop &&
              controller.views[secondPanel.id]?.url == secondURL,
              "URL and viewport edits must survive reopening and affect only the selected panel")
    let retainedWeb = try controller.views.values.first(where: { $0.url.isFileURL && $0.web != nil })?.web.unwrap("Missing local session")
    guard let retainedWeb else { throw CheckError.failed("Missing loaded HTML fixture") }
    _ = try javascript("window.scrimPageSession = 'in-memory'; document.body.dataset.draft = 'unfinished'", in: retainedWeb)
    let originalIDs = controller.records.map(\.id)
    controller.setEditing(true)
    storage.setData(try JSONEncoder().encode(controller.records), forKey: "page.1.panels")
    controller.selectPage(store.appendPage())
    try check(controller.records.isEmpty && store.currentPage == 1, "New canvas must start empty")
    controller.add(WidgetSpec(kind: .clock).url)
    let clockID = controller.records.first?.id
    controller.setEditing(false)
    func pageKey(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: controller.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                         isARepeat: false, keyCode: code)!
    }
    func sendPageKey(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [.option, .command]) {
        NSApp.postEvent(pageKey(code, flags), atStart: true)
        if let event = NSApp.nextEvent(matching: .keyDown, until: Date(timeIntervalSinceNow: 0.15), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }
    controller.panel.makeFirstResponder(nil)
    sendPageKey(123)
    try check(store.currentPage == 0 && controller.records.map(\.id) == originalIDs, "Left shortcut must restore first canvas")
    let sessionState = try javascript("window.scrimPageSession + ':' + document.body.dataset.draft", in: retainedWeb) as? String
    try check(controller.views.values.contains { $0.web === retainedWeb } && sessionState == "in-memory:unfinished",
              "Switching canvases must preserve the same live WebKit document")
    controller.panel.makeFirstResponder(retainedWeb)
    _ = try javascript("const field = document.createElement('input'); document.body.append(field); field.id='arrow-edit'; field.focus(); field.onkeydown = () => window.arrowReceived = true; true", in: retainedWeb)
    sendPageKey(124, [])
    try waitFor("web editor receives its arrow") { (try? javascript("window.arrowReceived === true", in: retainedWeb) as? Bool) == true }
    try check(store.currentPage == 0, "An editor must retain arrow navigation")
    _ = try javascript("document.activeElement.blur()", in: retainedWeb)
    store.pageArrowModifiers = NSEvent.ModifierFlags.option.rawValue
    sendPageKey(124, .option)
    try waitFor("arrow from focused web content switches canvas") { store.currentPage == 1 }
    try check(store.currentPage == 1 && controller.records.count == 1 && controller.records.first?.id == clockID, "Right shortcut must restore second canvas")
    controller.setEditing(true)
    controller.movePage(1, to: 0)
    try check(store.currentPage == 0 && controller.records.first?.id == clockID, "Moving a page must keep its content selected")
    controller.selectPage(1)
    try check(controller.records.map(\.id) == originalIDs, "Reordered neighbor must retain its panels")
    controller.movePage(0, to: 1)
    controller.selectPage(1)
    controller.removeCurrentPage(1)
    try check(store.pageCount == 1 && store.currentPage == 0 && controller.records.map(\.id) == originalIDs,
              "Deleting a canvas must preserve the neighboring canvas")
    controller.removeCurrentPage(0)
    try check(store.pageCount == 1, "The last canvas stays available")
    print("PASS: launch URL cleanup, interactive peek and preference, native WebKit click, Command normalization, settings and quit actions, delayed Today reset, browse-after-reset, cancellation")
}


@MainActor func showPeekReview() throws -> OverlayController {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scrim-peek-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("index.html")
    let rows = (1...60).map { "<p>スクロール位置 \($0)</p>" }.joined()
    let html = "<meta charset='utf-8'><style>body{font:20px system-ui;padding:24px;background:#fafafa;color:#222}button{font:inherit;padding:12px}p{padding:10px}</style><h1>一時表示の操作確認</h1><button onclick=\"this.textContent='クリック成功'\">クリックを確認</button>" + rows
    try html.write(to: file, atomically: true, encoding: .utf8)
    let store = SettingsStore(storage: MemorySettingsStorage())
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
    controller.show(.pinned, immediately: true); controller.setEditing(true); controller.add(file); controller.setEditing(false)
    controller.show(.peek, immediately: true)
    controller.onDismiss = { NSApp.terminate(nil) }
    NSApp.activate(ignoringOtherApps: true)
    return controller
}

/// Edit mode: hovering blurs a panel (snapshot) under a centered pill; a click anywhere fades in its menu face
/// over the blur, a drag moves the panel instead, right-click and the accessibility press also open it; menu items
/// switch clock style in place, open a widget's settings face directly, and duplicate the panel.
/// The panel handles these mouse events itself, so they are sent to it directly (no live pointer needed).
@MainActor func verifyPanelMenuClicks() throws {
    try verifyPanelResize()
    func hints(_ view: NSView) -> [PanelEditHint] { (view as? PanelEditHint).map { [$0] } ?? view.subviews.flatMap(hints) }
    for shared in [true, false] {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.sameLayoutOnAllDisplays = shared
        let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
        controller.show(.pinned); controller.setEditing(true)
        defer { controller.show(.hidden, immediately: true) }
        for kind in [WidgetKind.clock, .calculator, .upcoming, .notionTasks] { controller.add(WidgetSpec(kind: kind).url) }
        controller.root.layoutSubtreeIfNeeded(); controller.panel.displayIfNeeded()
        let root = controller.root
        for record in controller.records {
            let name = "\(WidgetSpec(url: record.url)?.kind.rawValue ?? "?") (shared: \(shared))"
            guard let view = controller.views[record.id], let hint = hints(view).first else { throw CheckError.failed("Missing menu pill: " + name) }
            view.layoutSubtreeIfNeeded()
            try check(!hint.isHidden && abs(hint.frame.midX - view.bounds.midX) < 1 && abs(hint.frame.midY - view.bounds.midY) < 1,
                      "Menu pill must be centered while editing: " + name)
            func hover(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber,
                                       context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            }
            view.mouseExited(with: hover(.mouseExited))
            try check(view.editChrome == (pill: false, blur: false), "Without hover, no pill and no blur: " + name)
            view.mouseEntered(with: hover(.mouseEntered))
            try check(view.editChrome == (pill: true, blur: true) && view.hasBlurSnapshot, "Hover must blur a snapshot of the panel and show the pill: " + name)
            for spot in [NSPoint(x: view.frame.midX, y: view.frame.midY), NSPoint(x: view.frame.maxX - 20, y: view.frame.maxY - 16),
                         NSPoint(x: view.frame.minX + 30, y: view.frame.minY + 30)] {
                try check(root.hitTest(spot) === view, "Every part of the panel must take the click: " + name)
            }
            func event(_ type: NSEvent.EventType, _ offset: CGFloat = 0) -> NSEvent {
                let p = view.convert(NSPoint(x: view.bounds.midX + offset, y: view.bounds.midY + 20), to: nil)
                return NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func closeMenu() throws {
                controller.closeDialog()
                try waitFor("menu closes: " + name) { !view.isShowingMenu }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            let before = view.frame
            controller.touch(record.id)  // what the overlay's mouse-down monitor does first
            view.mouseDown(with: event(.leftMouseDown)); view.mouseDragged(with: event(.leftMouseDragged, 2)); view.mouseUp(with: event(.leftMouseUp, 2))
            try waitFor("menu face from click: " + name) { view.isShowingMenu }
            try check(view.frame == before, "A click with a little jitter must not move the panel: " + name)
            try check(view.editChrome == (pill: false, blur: true), "The menu face replaces the pill and keeps the blur behind it: " + name)
            let shield = try root.subviews.compactMap { $0 as? OverlayDialogBackdrop }.first.unwrap("Missing settings backdrop")
            let host = try shield.dialogContent.unwrap("Missing centered panel settings")
            try check(host.superview === shield && controller.panelWithSettings === view
                        && abs(host.frame.midX - root.bounds.midX) < 1
                        && abs(host.frame.midY - root.bounds.midY) < 1
                        && view.currentMenu?.title == WidgetSpec(url: view.url)?.title,
                      "Panel settings must open at screen center and identify the current panel: " + name)
            try check(root.hitTest(NSPoint(x: view.frame.midX, y: view.frame.midY)) !== view,
                      "The settings overlay must take clicks: " + name)
            try closeMenu()
            view.mouseDown(with: event(.leftMouseDown)); view.mouseDragged(with: event(.leftMouseDragged, 60))
            let dragging = view.frame
            try check(view.editChrome == (pill: false, blur: true), "While dragging, keep the blur and hide the pill: " + name)
            view.mouseUp(with: event(.leftMouseUp, 60))
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            try check(!view.isShowingMenu && dragging.minX == before.minX + 60, "A drag must move the panel without opening the menu: " + name)
            view.rightMouseDown(with: event(.rightMouseDown))
            try waitFor("menu face from right-click: " + name) { view.isShowingMenu }
            try closeMenu()
            try check(hint.accessibilityPerformPress(), "Accessibility press must be handled: " + name)
            try waitFor("menu face from accessibility press: " + name) { view.isShowingMenu }
            try closeMenu()
            view.mouseExited(with: hover(.mouseExited))
            try check(view.editChrome == (pill: false, blur: false), "Leaving the panel must clear the blur and pill: " + name)
        }
        // Items: clock style switches in place, a widget settings face replaces the menu, duplicate adds a panel.
        func panel(_ kind: WidgetKind) throws -> PanelView {
            guard let record = controller.records.first(where: { WidgetSpec(url: $0.url)?.kind == kind }), let view = controller.views[record.id] else {
                throw CheckError.failed("Missing \(kind.rawValue)")
            }
            return view
        }
        func open(_ view: PanelView) throws {
            view.rightMouseDown(with: NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            try waitFor("menu face opens") { view.isShowingMenu }
        }
        let clock = try panel(.clock)
        try open(clock)
        try check(clock.currentMenu?.clockStyle == .analog, "Clock menu must show the current style")
        clock.chooseMenuItem(21)
        try check(clock.isShowingMenu && WidgetSpec(url: clock.url)?.clockStyle == .digital && clock.currentMenu?.clockStyle == .digital,
                  "Clock style must switch while the menu stays open and shows the new style")
        let zone = "Europe/Paris"
        clock.currentMenu?.toggleZone(zone)
        try check(clock.currentMenu?.digitalZones.contains(zone) == true, "Time zones must toggle from the menu face")
        controller.closeDialog()
        let agenda = try panel(.upcoming)
        try open(agenda)
        let host = try root.subviews.compactMap { $0 as? OverlayDialogBackdrop }.first?.dialogContent
            .unwrap("Missing centered calendar settings")
        try check(controller.panelWithSettings === agenda && (host?.frame.width ?? 0) >= min(640, root.bounds.width - 24),
                  "Calendar settings must use the screen width even on a small panel")
        controller.closeDialog()
        let count = controller.records.count
        let calculator = try panel(.calculator)
        try open(calculator)
        calculator.chooseMenuItem(2)
        try check(controller.records.count == count + 1, "Duplicate must add a panel")
        try waitFor("menu closes after an action") { !calculator.isShowingMenu }
    }
    print("PASS: centered panel settings and title, hover blur and pill, click/right-click/accessibility, drag without opening settings, clock style and zones, calendar settings, duplicate (shared and per-display layouts)")
}

@MainActor private func verifyPanelResize() throws {
    let store = SettingsStore(storage: MemorySettingsStorage())
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
    controller.show(.pinned, immediately: true)
    defer { controller.show(.hidden, immediately: true) }
    controller.setEditing(true)
    controller.add(WidgetSpec(kind: .calculator).url)
    let view = try controller.views.values.first.unwrap("Missing resize panel")
    let grid = PanelGrid(screen: controller.root.bounds.size)
    let original = grid.frame(column: 4, row: 3, columns: 3, rows: 2)
    let dx = grid.step.width, dy = grid.step.height
    let locations: [(column: Int, row: Int)] = [
        (0, 0), (0, 2), (2, 0), (2, 2), (0, 1), (2, 1), (1, 0), (1, 2), (1, 1)
    ]
    for (column, row) in locations {
        view.frame = original
        view.layoutSubtreeIfNeeded()
        let corner = column != 1 && row != 1
        let inset: CGFloat = corner ? 20 : 11
        let x = [inset, view.bounds.midX, view.bounds.maxX - inset][column]
        let y = [inset, view.bounds.midY, view.bounds.maxY - inset][row]
        let start = view.convert(NSPoint(x: x, y: y), to: nil)
        let end = NSPoint(x: start.x + (column == 0 ? -dx : dx), y: start.y + (row == 0 ? -dy : dy))
        func event(_ type: NSEvent.EventType, at location: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        NSCursor.iBeam.set()
        controller.panel.sendEvent(event(.mouseMoved, at: start))
        let cursor = NSCursor.current
        try check(cursor !== NSCursor.iBeam && (cursor === NSCursor.openHand) == (column == 1 && row == 1),
                  "Edit-mode pointer must match the resize or move region")
        if #available(macOS 15.0, *), corner {
            let positions: [[NSCursor.FrameResizePosition]] = [[.bottomLeft, .topLeft], [.bottomRight, .topRight]]
            let expected = NSCursor.frameResize(position: positions[column / 2][row / 2], directions: .all)
            try check(cursor.image.tiffRepresentation == expected.image.tiffRepresentation,
                      "All four corners must show the matching diagonal cursor")
        }
        view.mouseDown(with: event(.leftMouseDown, at: start))
        view.mouseDragged(with: event(.leftMouseDragged, at: end))
        view.mouseUp(with: event(.leftMouseUp, at: end))
        let expectedColumn = column == 0 ? 3 : column == 1 && row == 1 ? 5 : 4
        let expectedRow = row == 0 ? 2 : column == 1 && row == 1 ? 4 : 3
        let expected = grid.frame(column: expectedColumn, row: expectedRow,
                                  columns: column == 1 ? 3 : 4, rows: row == 1 ? 2 : 3)
        try check(view.frame.equalTo(expected), "Drag must move or resize the intended edges and snap to the grid")
    }
    NSCursor.arrow.set()
    print("PASS: eight resize targets, diagonal cursors, center drag and grid snapping")
}

/// Hidden overlays free their web pages (idle release and memory pressure use this path); the next show reloads them.
@MainActor func verifyWebRelease(fixture: URL) throws {
    let store = SettingsStore(storage: MemorySettingsStorage())
    let controller = OverlayController(store: store, websiteDataStore: .nonPersistent())
    controller.show(.pinned); controller.setEditing(true)
    defer { controller.show(.hidden, immediately: true) }
    controller.add(fixture); controller.add(WidgetSpec(kind: .clock).url)
    controller.setEditing(false)
    guard let page = controller.views.values.first(where: { $0.web != nil }) else { throw CheckError.failed("Missing web panel") }
    try waitFor("web panel loads") { page.web?.isLoading == false }
    controller.releaseWebPanels(force: true)
    try check(page.web != nil, "Web pages must not be released while the overlay is shown")
    controller.show(.hidden, immediately: true)
    store.releasesIdleWebPanels = false
    controller.releaseWebPanels(force: false)
    try check(page.web != nil, "Turning the setting off must keep web pages")
    controller.releaseWebPanels(force: true)
    try check(page.web == nil, "Releasing must free the web page while hidden")
    try check(controller.views.values.contains { WidgetSpec(url: $0.url)?.kind == .clock && $0.isLive }, "Native widgets stay")
    controller.show(.pinned)
    try waitFor("web page reloads on show") { page.web != nil && page.web?.isLoading == false }
}
