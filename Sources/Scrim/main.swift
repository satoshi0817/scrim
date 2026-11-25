import AppKit
import ScrimCore
import ScrimAssets
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: SettingsStore
    private var meetingBadge: MeetingNotchBadge?
    var overlay: OverlayController!
    var settings: SettingsController!
    let input = InputController()
    let gestureInput = DoublePressInput()
    private var gestureItem: NSMenuItem!
    var machine = HoldTapStateMachine()
    var item: NSStatusItem!
    private var registrationItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var pendingFiles: [URL] = []
    private var readyForFiles = false
    private var openingFiles = false
    private var receivedLaunchFiles = false
    // Injectable: previews/tests never need to present the production panel.
    var chooseFiles: (@escaping ([URL]) -> Void) -> Void = { completion in
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .html, .plainText, .rtf, UTType(filenameExtension: "xhtml") ?? .html,
                                    UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "log") ?? .plainText]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.begin { response in completion(response == .OK ? panel.urls : []) }
    }
    #if DEBUG || TRIAL_DIAGNOSTICS
    var diagnostics = Diagnostics()
    var began: Double?
    #endif
    init(store: SettingsStore) { self.store = store }
    func applicationDidFinishLaunching(_ notification: Notification) {
        ReleaseUpdater.shared.start()
        SettingsController.applyAppearance(store.appearanceMode)
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        let obsolete = URL(string: "scrim-widget://inbox")!
        if store.panels.contains(where: { $0.url == obsolete }) { store.panels.removeAll { $0.url == obsolete } }
        var layouts = store.layoutsByDisplay
        for key in layouts.keys where layouts[key]?.panels.contains(where: { $0.url == obsolete }) == true {
            layouts[key]?.panels.removeAll { $0.url == obsolete }
            store.layoutsByDisplay = layouts
        }
        store.normalizeWebLaunchURLs()
        store.shareLegacyDisplayContent()
        // Only the running app reads the Keychain; verification runs keep the empty in-memory store.
        NotionEnvironment.current = NotionEnvironment(tokens: KeychainNotionTokenStore(), baseURL: NotionAPI.baseURL)
        PanelTextAppearance.shared.load(from: store)
        overlay = OverlayController(store: store); settings = SettingsController(store: store)
        meetingBadge = MeetingNotchBadge(store: store)
        overlay.isSettingsKey = { [weak self] in self?.settings.window.isKeyWindow ?? false }
        overlay.onOpenSettings = { [weak self] in self?.openSettings() }
        overlay.onDismiss = { [weak self] in self?.gestureInput.cancelPendingGesture(); self?.machine.dismiss(); self?.apply() }
        settings.registerShortcut = { [unowned self] candidate in self.input.registerReplacement(candidate) }
        settings.recordingBegan = { [weak self] in self?.gestureInput.stop() }
        settings.recordingCancelled = { [weak self] in self?.input.restoreActiveRegistrationFeedback(); if let self { self.gestureInput.start(settings: self.store.gesture, allowsPeekInteraction: self.store.peekAllowsInteraction) } }
        settings.shortcutCommitted = { [weak self] in guard let self else { return }; self.gestureInput.start(settings: self.store.gesture, allowsPeekInteraction: self.store.peekAllowsInteraction); self.refreshEntry() }
        settings.dockChanged = { [weak self] in self?.applyDockPolicy() }
        settings.changed = { [weak self] in guard let self else { return }; if self.settings.embeddedWindow == nil { self.machine.dismiss() }; self.apply(); self.input.configure(self.store) }
        input.onEdge = { [weak self] down, fallback in
            guard let self else { return }
            if self.settings.recordingPageKeys { return }
            if self.settings.isRecording {
                if down && self.store.method == .carbon { self.settings.receiveShortcut(self.store.shortcut) }
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if down { self.machine.press(at: now, toggle: fallback) }
            else if fallback { if self.machine.state == .peek { self.machine.fallback() } }
            else { self.machine.release(at: now) }
            #if DEBUG || TRIAL_DIAGNOSTICS
            if down { self.began = now; self.diagnostics.deltaMS = nil; self.diagnostics.release = "none" }
            else { self.diagnostics.deltaMS = self.began.map { (now-$0)*1000 }; self.diagnostics.heldMS = self.diagnostics.deltaMS ?? 0; self.diagnostics.release = self.input.diagnosticSource; self.began = nil }
            #endif
            self.apply()
        }
        #if DEBUG || TRIAL_DIAGNOSTICS
        settings.diagnosticText = { [weak self] in
            guard let self else { return Diagnostics().text }
            var d = self.diagnostics; if let began = self.began { d.heldMS = (ProcessInfo.processInfo.systemUptime-began)*1000 }
            d.keyCode = self.input.observedModifierKeyCode; d.permission = AppGesturePermission().isGranted(); d.panels = self.overlay.records.count; d.live = self.overlay.views.values.filter { $0.isLive }.count; d.rss = processRSS(); return d.text
        }
        #endif
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Scrim"
        let menu = NSMenu()
        gestureItem = NSMenuItem(title: "", action: nil, keyEquivalent: ""); menu.addItem(gestureItem)
        openItem = NSMenuItem(title: "", action: #selector(openOverlay), keyEquivalent: ""); openItem.target = self; menu.addItem(openItem)
        menu.addItem(withTitle: "レイアウトを編集…", action: #selector(editLayout), keyEquivalent: "").target = self
        menu.addItem(fileOpenItem())
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        registrationItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: "")
        registrationItem.target = self; registrationItem.isHidden = true; menu.addItem(registrationItem)
        menu.addItem(.separator()); menu.addItem(withTitle: "Scrim を終了", action: #selector(quit), keyEquivalent: "q").target = self; item.menu = menu
        input.onRegistrationChange = { [weak self] status in
            guard let self else { return }
            self.settings.registrationStatus = status
            self.refreshEntry()
        }
        gestureInput.onEffect = { [weak self] effect in
            guard let self, !self.settings.recordingAnyKeys else { return }
            switch effect {
            case .none: return
            case .peek:
                if self.machine.state != .pinned { self.overlay.show(.peek) }
            case .pin:
                if self.machine.state == .pinned { self.machine.dismiss() }
                else { self.machine.pin() }
                self.apply()
            case .hide: self.machine.dismiss(); self.apply()
            case .hideImmediately: self.machine.dismiss(); self.overlay.show(.hidden, immediately: true)
            }
        }
        gestureInput.onStatus = { [weak self] in self?.refreshEntry(); self?.settings.refresh() }
        settings.gestureChanged = { [weak self] in guard let self else { return }; self.gestureInput.start(settings: self.store.gesture, allowsPeekInteraction: self.store.peekAllowsInteraction); self.refreshEntry() }
        settings.gestureAvailable = { [weak self] in self?.gestureInput.available ?? false }
        gestureInput.start(settings: store.gesture, allowsPeekInteraction: store.peekAllowsInteraction)
        input.configure(store)
        refreshEntry(); applyDockPolicy()
        let firstRun = store.beginFirstRunGuidance()
        readyForFiles = true
        // Defer guidance until launch-time open events have been drained.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.pendingFiles.isEmpty {
                let urls = self.pendingFiles; self.pendingFiles.removeAll(); self.openFiles(urls)
            } else if !self.receivedLaunchFiles {
                if firstRun || self.input.registrationStatus.message != nil { self.openSettings() }
                if firstRun { self.settings.firstRunGuidance() }
            }
        }
    }
    /// Gestures and shortcuts are ignored on displays with the overlay turned off; menu actions are `explicit`.
    func apply(explicit: Bool = false) {
        if !overlay.show(machine.state, explicit: explicit) { machine.dismiss() }
    }
    private func fileOpenItem() -> NSMenuItem {
        let item = NSMenuItem(title: "ファイルを開く…", action: #selector(openFilePanel), keyEquivalent: "o")
        item.keyEquivalentModifierMask = [.command]; item.target = self; return item
    }
    private func applyDockPolicy() {
        NSApp.setActivationPolicy(store.dockVisible ? .regular : .accessory)
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "Scrim")
        appMenu.addItem(withTitle: "Scrim を終了", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; main.addItem(appItem)
        let file = NSMenuItem(); let fileMenu = NSMenu(title: "ファイル")
        fileMenu.addItem(fileOpenItem()); file.submenu = fileMenu; main.addItem(file)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "編集")
        for (title, action, key) in [("元に戻す", "undo:", "z"), ("切り取り", "cut:", "x"),
                                     ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"), ("すべてを選択", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let redo = NSMenuItem(title: "やり直す", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(redo, at: 1)
        edit.submenu = editMenu; main.addItem(edit)
        let view = NSMenuItem(); let viewMenu = NSMenu(title: "表示")
        viewMenu.addItem(withTitle: "レイアウトを編集…", action: #selector(editLayout), keyEquivalent: "").target = self
        view.submenu = viewMenu; main.addItem(view)
        NSApp.mainMenu = main
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedLaunchFiles = true; openingFiles = true
        guard readyForFiles else { pendingFiles.append(contentsOf: urls); return }
        openFiles(urls)
    }
    private func openFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        openingFiles = true; settings.cancelRecording(); settings.window.orderOut(nil)
        machine.pin()
        // Re-select the pointer display before adding, even when already pinned.
        overlay.show(.hidden, immediately: true); apply(explicit: true)
        overlay.setEditing(true)
        for url in urls { overlay.add(url) }
        DispatchQueue.main.async { [weak self] in self?.openingFiles = false }
    }
    @objc private func openFilePanel() {
        chooseFiles { [weak self] urls in self?.openFiles(urls) }
    }
    private func refreshEntry() {
        guard item != nil else { return }
        gestureItem.title = GestureCopy.menu(permitted: gestureInput.available, secure: gestureInput.secure, fn: store.gesture.useFn)
        let entry = EntryState(shortcut: store.shortcut, registration: input.registrationStatus)
        openItem.title = entry.openTitle
        registrationItem.title = entry.failureMessage ?? ""; registrationItem.isHidden = !entry.showsWarning
        item.button?.title = ""; item.button?.image = StatusIcon.image(warning: entry.showsWarning)
    }
    @objc private func openOverlay() { settings.cancelRecording(); machine.pin(); apply(explicit: true) }
    @objc private func editLayout() {
        settings.cancelRecording(); settings.window.orderOut(nil)
        machine.pin(); apply(explicit: true); overlay.setEditing(true)
    }
    @objc func openSettings() {
        guard settings != nil else { return }
        gestureInput.cancelPendingGesture()
        machine.pin(); apply(explicit: true); NSApp.activate(ignoringOtherApps: true); overlay.presentSettings(settings)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !openingFiles { openSettings() }
        return true
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let editor = overlay?.panel.firstResponder as? NoteTextView { editor.window?.makeFirstResponder(nil) }
        guard overlay?.notes.saveAll() == false else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "保存できていないメモがあります"
        alert.window.level = NSWindow.Level(rawValue: overlay.panel.level.rawValue + 1)
        alert.informativeText = "編集に戻ると、メモの保存を再試行できます。"
        alert.addButton(withTitle: "編集に戻る")
        alert.addButton(withTitle: "保存せずに終了").hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { input.stop(); gestureInput.stop() }
}

let supportedOptions: Set<String> = ["--peek-review", "--verify-panel-behavior", "--verify-fades", "--verify-widgets", "--widgets-review", "--verify-input-monitoring", "--verify-content",
    "--verify-settings", "--settings-review", "--inspect-calendar-login", "--verify-interactions", "--interaction-review", "--render-previews",
    "--verify-notion-tasks", "--verify-panel-menu"]
if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") && !supportedOptions.contains($0) }) {
    fputs("Unsupported command-line option.\n", stderr); exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
#if DEBUG
if Bundle.main.bundleIdentifier == "com.satoshi0817.ScrimReview" {
    let review = try MainActor.assumeIsolated { try showPeekReview() }
    withExtendedLifetime(review) { app.run() }; exit(0)
}
#endif
if CommandLine.arguments.contains("--peek-review") {
    let review = try MainActor.assumeIsolated { try showPeekReview() }
    withExtendedLifetime(review) { app.run() }; exit(0)
}
if CommandLine.arguments.contains("--verify-panel-behavior") {
    do { try verifyPanelBehavior() }
    catch { fputs("Panel verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--verify-fades") {
    Task { @MainActor in
        do { try await verifyOverlayFades(); exit(0) }
        catch { fputs("Fade verification failed: \(error)\n", stderr); exit(1) }
    }
    app.run(); exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--verify-widgets") {
    guard index+1 < CommandLine.arguments.count else { fputs("Provide a local forecast fixture\n", stderr); exit(2) }
    let url = URL(fileURLWithPath: CommandLine.arguments[index+1])
    Task { @MainActor in
        do { try await verifyWidgets(forecast: url); exit(0) }
        catch { fputs("Widget verification failed: \(error)\n", stderr); exit(1) }
    }
    app.run(); exit(0)
}
if CommandLine.arguments.contains("--widgets-review") {
    let review = MainActor.assumeIsolated { showWidgetsReview() }
    withExtendedLifetime(review) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--verify-input-monitoring") {
    do { try verifyInputMonitoringRecovery() }
    catch { fputs("Input monitoring verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--verify-content") {
    do { try verifyContentPanels() }
    catch { fputs("Content verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--verify-settings") {
    do { try verifyNativeSettings() }
    catch { fputs("Settings verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--settings-review") {
    let review = SettingsController(store: SettingsStore(storage: MemorySettingsStorage()), permissionState: { false }, loginService: FakeLoginItemService())
    review.show()
    withExtendedLifetime(review) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--inspect-calendar-login") {
    do { try inspectCalendarLogin() }
    catch { fputs("Calendar inspection failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--verify-panel-menu") {
    do { try MainActor.assumeIsolated { try verifyPanelMenuClicks() } }
    catch { fputs("Panel menu verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--verify-notion-tasks") {
    guard index+1 < CommandLine.arguments.count, let fixture = URL(string: CommandLine.arguments[index+1]),
          fixture.host == "127.0.0.1" else { fputs("Provide a local Notion fixture URL\n", stderr); exit(2) }
    do { try MainActor.assumeIsolated { try verifyNotionTasks(fixture: fixture) } }
    catch { fputs("Notion task verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--verify-interactions") {
    guard index+1 < CommandLine.arguments.count, let fixture = URL(string: CommandLine.arguments[index+1]),
          fixture.host == "127.0.0.1" else { fputs("Provide a local fixture URL\n", stderr); exit(2) }
    do { try verifyInteractions(fixture: fixture) }
    catch { fputs("Interaction verification failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--interaction-review") {
    guard index+1 < CommandLine.arguments.count, let fixture = URL(string: CommandLine.arguments[index+1]),
          fixture.host == "127.0.0.1" else { fputs("Provide a local fixture URL\n", stderr); exit(2) }
    let review = showInteractionReview(fixture: fixture)
    withExtendedLifetime(review) { app.run() }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
    guard index+1 < CommandLine.arguments.count else { fputs("Missing preview directory\n", stderr); exit(2) }
    do { try renderPreviews(directory: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true)) }
    catch { fputs("Preview rendering failed\n", stderr); exit(1) }
    exit(0)
}
let environment = ProcessInfo.processInfo.environment
guard Bundle.main.bundleIdentifier == SettingsMigration.destinationDomain || environment["SCRIM_DEFAULTS_SUITE"] != nil else {
    fputs("Run the packaged Scrim app or provide an isolated SCRIM_DEFAULTS_SUITE.\n", stderr); exit(2)
}
guard let defaults = SettingsDefaultsPolicy.open(
    environment: environment,
    openSuite: { UserDefaults(suiteName: $0) },
    standard: { UserDefaults.standard }
) else { fatalError("Cannot open Scrim settings suite override") }
if SettingsMigration.shouldMigrate(environment: environment) {
    // Read the old domain through the new defaults object; never open or write an old suite.
    SettingsMigration.migrate(
        sources: [SettingsMigration.legacyDomain, SettingsMigration.oldestDomain].map {
            UserDefaultsMigrationSource(defaults: defaults, domain: $0)
        },
        destination: UserDefaultsMigrationStorage(defaults: defaults, domain: SettingsMigration.destinationDomain))
}
let store = SettingsStore(defaults: defaults)
if environment["SCRIM_DEFAULT_SHORTCUT"] == "ctrl-opt-cmd-f19" { store.shortcut = .testCopy }
let delegate = AppDelegate(store: store)
app.delegate = delegate
app.run()
