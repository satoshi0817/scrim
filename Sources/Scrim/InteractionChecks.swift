import AppKit
import SwiftUI
import WebKit
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
    _ = try javascript("document.getElementById('blank').click()", in: web)
    try waitFor("target blank popup") { view.browser.popupWebViews.first?.url?.path == "/popup" && view.browser.popupWebViews.first?.isLoading == false }
    view.browser.closeAll()
    _ = try javascript("document.getElementById('login').click()", in: web)
    try waitFor("popup") { view.browser.popupWebViews.first?.url?.path == "/popup" && view.browser.popupWebViews.first?.isLoading == false }
    guard let popup = view.browser.popupWebViews.first else { throw CheckError.failed("Missing popup") }
    let text = try javascript("document.body.innerText", in: popup) as? String ?? ""
    try check(text.contains("テスト用ログイン"), "Popup must receive opener cookies")
    view.sleep()
    try check(view.web === web, "An OAuth opener must stay alive while popup is open")
    _ = try javascript("document.getElementById('continue').click()", in: popup)
    try waitFor("opener callback and redirect") { web.url?.path == "/signed-in" && !web.isLoading }
    let signedIn = try javascript("document.body.innerText", in: web) as? String ?? ""
    try check(signedIn.contains("signed-in"), "POST, redirect, HttpOnly cookies and opener messaging must work")
    let storageCallback = try javascript("localStorage.getItem('storageCallback')", in: web) as? String
    try check(storageCallback == "received", "Calendar-style storage callback must reach opener")
    try waitFor("window.close") { !view.browser.hasOpenWindows }
    view.reloadContent()
    try waitFor("restored session") { view.web?.isLoading == false && view.web?.url?.path == "/signed-in" }
    let restored = try javascript("document.body.innerText", in: view.web!) as? String ?? ""
    try check(restored.contains("signed-in"), "Recreated WebKit view must retain session")
    controller.setEditing(true); view.command?(3)
    try check(controller.records.isEmpty, "Edit mode must permit closure")
    print("PASS: mode lock, title-free content, display-relative grid drag, edit-only add/close, OAuth popup, cookies, POST redirect, opener + storage callbacks, window.close, session restoration")
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

func verifyContentPanels() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Scrim-Content-"+UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }
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
        (panel.subviews.compactMap { $0 as? NativeTextPanel }.first?.documentView as? NSTextView)
    }
    try check(textView(text)?.string == contents && textView(text)?.isEditable == false, "Text must render literally in a read-only native view")
    try check(text.canEditContent, "Managed contents must expose edit action")
    let updated = "更新したメモ"
    try documents.replace(updated, at: textURL); text.reloadContent()
    try check(textView(text)?.string == updated, "Edited text must reload")
    text.sleep(); text.wake()
    try check(textView(text)?.string == updated, "Text must survive sleep and wake")
    let utf16 = temp.appendingPathComponent("unicode.txt")
    try "UTF-16 のテキスト".write(to: utf16, atomically: true, encoding: .utf16)
    controller.add(utf16)
    guard let external = controller.views.values.first(where: { $0.url == utf16 }) else { throw CheckError.failed("Missing external text") }
    try check(textView(external)?.string == "UTF-16 のテキスト" && !external.canEditContent, "External text must decode without exposing managed editing")
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
    try "<!doctype html><meta charset='utf-8'><link rel='stylesheet' href='../assets/style.css'><h1>Embedded file</h1><img src='../assets/logo.svg'><script src='../assets/app.js'></script>".write(to: entry, atomically: true, encoding: .utf8)
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
    print("PASS: managed text/HTML creation, literal native text, Unicode decoding, edit/reload, sleep/wake, external-write guard, per-document HTML scope, close preserves file")
    print("PASS: HTML folder import, nested entry, relative images/CSS/JS, original source removal")
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
        return (1...8).map { WeatherHour(date: Date().addingTimeInterval(Double($0)*10800), temperature: Double(14+$0), precipitationProbability: $0*10, code: $0 % 2 == 0 ? 2 : 61) }
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
    try check(!sf.working(beforeDST) && sf.working(afterDST) && london.working(afterDST), "US and UK daylight-saving rules must be independent")
    let overnight = WorkCity(id: "Asia/Tokyo", start: 22, end: 6)
    try check(overnight.working(iso.date(from: "2026-03-06T17:00:00Z")!) && !overnight.working(iso.date(from: "2026-03-08T17:00:00Z")!), "Night shifts must use the weekday on which the shift starts")
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
    try check(agenda.model.isEditing, "Agenda settings button must appear while editing")
    let presentation = agenda.model.upcoming.presentationRevision
    controller.show(.hidden, immediately: true)
    controller.show(.peek, immediately: true)
    try check(agenda.model.upcoming.presentationRevision == presentation + 1, "Reopening must reset agenda scroll when enabled")
    controller.show(.pinned, immediately: true)
    try check(agenda.model.upcoming.presentationRevision == presentation + 1, "Pinning a visible peek must preserve scroll")
    store.agendaResetsScrollOnOpen = false
    controller.show(.hidden, immediately: true)
    controller.show(.pinned, immediately: true)
    try check(agenda.model.upcoming.presentationRevision == presentation + 1, "Disabled reset must preserve scroll on reopen")
    controller.setEditing(true)
    agenda.model.upcoming.select([options[0].id])
    agenda.model.upcoming.setDisplayDays(14)
    let persistedKeyword = agenda.model.upcoming.addExcludedKeyword()
    agenda.model.upcoming.editExcludedKeyword(persistedKeyword, text: "除外する予定")
    let agendaRecord = try store.panels.first(where: { WidgetSpec(url: $0.url)?.kind == .upcoming }).unwrap("Missing saved agenda")
    try check(WidgetSpec(url: agendaRecord.url)?.calendarIDs == chosen && WidgetSpec(url: agendaRecord.url)?.agendaDays == 14 && WidgetSpec(url: agendaRecord.url)?.excludedKeywords == ["除外する予定"], "Calendar filter, day count and keywords must persist together on the panel")
    agenda.superview?.layoutSubtreeIfNeeded()
    agenda.layoutSubtreeIfNeeded()
    (agenda.superview as? PanelView)?.performMenuAction(22)
    try check(agenda.allowsControl(at: NSPoint(x: agenda.bounds.midX, y: agenda.bounds.midY)), "Settings face must allow controls through edit-mode hit testing")
    controller.setEditing(false)
    try check(!agenda.model.upcoming.isConfiguring && !agenda.model.isEditing, "Leaving edit mode must return to agenda face")
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
    filtered.isConfiguring = false
    let back = NSHostingView(rootView: UpcomingEventsView(model: filtered, now: Date(), size: CGSize(width: 340, height: 420), editing: true))
    back.frame = NSRect(x: 0, y: 0, width: 340, height: 420)
    reviewWindow.setContentSize(NSSize(width: 340, height: 420))
    reviewWindow.contentView = back; reviewWindow.orderFront(nil); back.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    filtered.isConfiguring = true
    try await Task.sleep(nanoseconds: 180_000_000)
    if let bitmap = back.bitmapImageRepForCachingDisplay(in: back.bounds) {
        back.cacheDisplay(in: back.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".tmp/upcoming-flip-review.png"))
    }
    try await Task.sleep(nanoseconds: 350_000_000)
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
    func sendCommandComma() {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)!
        NSApp.sendEvent(event)
    }
    try check(toolbar.isHidden, "Pinned HUD must start hidden")
    sendCommandComma()
    try check(controller.showingActions && toolbar.isHidden, "Command-comma must open the centered action list")
    sendCommandComma()
    try check(!controller.showingActions, "Command-comma must dismiss the action list")
    sendCommandComma()
    for (key, chars) in [(125, "\u{f701}"), (36, "\r")] {
        NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(key))!)
    }
    try check(openedSettings && dialogSettings.embeddedWindow === controller.panel && !dialogSettings.window.isVisible,
              "Arrow and Return must open settings inside the overlay")
    controller.closeDialog()
    try check(dialogSettings.embeddedWindow == nil, "Closing settings must release the overlay presentation")
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
    print("PASS: launch URL cleanup, interactive peek and preference, native WebKit click, Command normalization, settings route, delayed Today reset, browse-after-reset, cancellation")
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
