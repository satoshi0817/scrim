import AppKit
import SheerpaneCore
import SheerpaneAssets

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: SettingsStore
    var overlay: OverlayController!
    var settings: SettingsController!
    let input = InputController()
    var machine = HoldTapStateMachine()
    var item: NSStatusItem!
    private var registrationItem: NSMenuItem!
    private var openItem: NSMenuItem!
    #if DEBUG || TRIAL_DIAGNOSTICS
    var diagnostics = Diagnostics()
    var began: Double?
    #endif
    init(store: SettingsStore) { self.store = store }
    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(store: store); settings = SettingsController(store: store)
        overlay.isSettingsKey = { [weak self] in self?.settings.window.isKeyWindow ?? false }
        overlay.onDismiss = { [weak self] in self?.machine.dismiss(); self?.apply() }
        settings.registerShortcut = { [unowned self] candidate in self.input.registerReplacement(candidate) }
        settings.recordingBegan = { [weak self] in self?.machine.dismiss(); self?.apply() }
        settings.recordingCancelled = { [weak self] in self?.input.restoreActiveRegistrationFeedback() }
        settings.shortcutCommitted = { [weak self] in self?.refreshEntry() }
        settings.dockChanged = { [weak self] in self?.applyDockPolicy() }
        settings.changed = { [weak self] in guard let self else { return }; self.machine.dismiss(); self.apply(); self.input.configure(self.store) }
        input.onEdge = { [weak self] down, fallback in
            guard let self else { return }
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
            d.keyCode = self.input.observedModifierKeyCode; d.permission = CGPreflightListenEventAccess(); d.panels = self.overlay.pool.entries.count; d.live = self.overlay.views.values.filter { $0.web != nil }.count; d.rss = processRSS(); return d.text
        }
        #endif
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Sheerpane"
        let menu = NSMenu()
        openItem = NSMenuItem(title: "", action: #selector(openOverlay), keyEquivalent: ""); openItem.target = self; menu.addItem(openItem)
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        registrationItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: "")
        registrationItem.target = self; registrationItem.isHidden = true; menu.addItem(registrationItem)
        menu.addItem(.separator()); menu.addItem(withTitle: "Sheerpane を終了", action: #selector(quit), keyEquivalent: "q").target = self; item.menu = menu
        input.onRegistrationChange = { [weak self] status in
            guard let self else { return }
            self.settings.registrationStatus = status
            self.refreshEntry()
        }
        input.configure(store)
        refreshEntry(); applyDockPolicy()
        let firstRun = !store.guided
        if firstRun { store.guided = true }
        if firstRun || input.registrationStatus.message != nil { settings.show() }
    }
    func apply() { overlay.show(machine.state) }
    private func applyDockPolicy() { NSApp.setActivationPolicy(store.dockVisible ? .regular : .accessory) }
    private func refreshEntry() {
        guard item != nil else { return }
        let entry = EntryState(shortcut: store.shortcut, registration: input.registrationStatus)
        openItem.title = entry.openTitle
        registrationItem.title = entry.failureMessage ?? ""; registrationItem.isHidden = !entry.showsWarning
        item.button?.title = ""; item.button?.image = StatusIcon.image(warning: entry.showsWarning)
    }
    @objc private func openOverlay() { settings.cancelRecording(); machine.pin(); apply() }
    @objc func openSettings() {
        guard settings != nil else { return }
        machine.dismiss(); apply(); settings.show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { input.stop() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
    guard index+1 < CommandLine.arguments.count else { fputs("Missing preview directory\n", stderr); exit(2) }
    do { try renderPreviews(directory: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true)) }
    catch { fputs("Preview rendering failed\n", stderr); exit(1) }
    exit(0)
}
let environment = ProcessInfo.processInfo.environment
guard let defaults = SettingsDefaultsPolicy.open(
    environment: environment,
    openSuite: { UserDefaults(suiteName: $0) },
    standard: { UserDefaults.standard }
) else { fatalError("Cannot open Sheerpane settings suite override") }
if SettingsMigration.shouldMigrate(environment: environment) {
    // Read the old domain through the new defaults object; never open or write an old suite.
    SettingsMigration.migrate(
        source: UserDefaultsMigrationStorage(defaults: defaults, domain: SettingsMigration.legacyDomain),
        destination: UserDefaultsMigrationStorage(defaults: defaults, domain: SettingsMigration.destinationDomain))
}
let store = SettingsStore(defaults: defaults)
if environment["SHEERPANE_DEFAULT_SHORTCUT"] == "ctrl-opt-cmd-f19" { store.shortcut = .testCopy }
let delegate = AppDelegate(store: store)
app.delegate = delegate
app.run()
