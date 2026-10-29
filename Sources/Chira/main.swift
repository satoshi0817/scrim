import AppKit
import ChiraCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: SettingsStore
    var overlay: OverlayController!
    var settings: SettingsController!
    let input = InputController()
    var machine = HoldTapStateMachine()
    var item: NSStatusItem!
    #if DEBUG || TRIAL_DIAGNOSTICS
    var diagnostics = Diagnostics()
    var began: Double?
    #endif
    init(store: SettingsStore) { self.store = store }
    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(store: store); settings = SettingsController(store: store)
        overlay.onDismiss = { [weak self] in self?.machine.dismiss(); self?.apply() }
        settings.changed = { [weak self] in guard let self else { return }; self.machine.dismiss(); self.apply(); self.input.configure(self.store) }
        input.onEdge = { [weak self] down, fallback in
            guard let self else { return }
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
            d.keyCode = self.store.side.keyCode; d.permission = CGPreflightListenEventAccess(); d.panels = self.overlay.pool.entries.count; d.live = self.overlay.views.values.filter { $0.web != nil }.count; d.rss = processRSS(); return d.text
        }
        #endif
        input.configure(store)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); item.button?.title = "Chira"
        let menu = NSMenu(); menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator()); menu.addItem(withTitle: "Chira を終了", action: #selector(quit), keyEquivalent: "q").target = self; item.menu = menu
        if !store.guided { store.guided = true; settings.show() }
    }
    func apply() { overlay.show(machine.state) }
    @objc func openSettings() { settings.show() }
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
let suite = environment["CHIRA_DEFAULTS_SUITE"] ?? "com.satoshi0817.Chira"
guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Cannot open Chira settings") }
let store = SettingsStore(defaults: defaults)
if environment["CHIRA_DEFAULT_SHORTCUT"] == "ctrl-opt-cmd-f19" { store.shortcut = .testCopy }
let delegate = AppDelegate(store: store)
app.delegate = delegate
app.run()
