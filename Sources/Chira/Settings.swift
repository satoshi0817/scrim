import AppKit
import ChiraCore
#if DEBUG || TRIAL_DIAGNOSTICS
import Darwin
#endif

final class SettingsController: NSObject {
    let store: SettingsStore
    let window: NSWindow
    var changed: (() -> Void)?
    private var method: NSPopUpButton!
    private var side: NSPopUpButton!
    private var permission: ActionButton!
    private var note: NSTextField!
    private var recorder: ShortcutRecorder!
    #if DEBUG || TRIAL_DIAGNOSTICS
    var diagnosticText: (() -> String)?
    private var diagnosticLabel: NSTextField!
    private var timer: Timer?
    #endif
    init(store: SettingsStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Chira 設定"; window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 700)); root.wantsLayer = true; root.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor; window.contentView = root
        func text(_ value: String, _ y: CGFloat, _ size: CGFloat = 14) { let v = label(value, size: size); v.frame = NSRect(x: 28, y: y, width: 560, height: 30); root.addSubview(v) }
        text("Chira", 642, 26)
        text("押している間だけ表示。短く押すと固定します。", 602)
        text("固定中は Esc・背景クリック・同じショートカットで閉じます。", 574)
        text("ショートカット（欄を選択してキーを入力）", 526)
        recorder = ShortcutRecorder(frame: NSRect(x: 28, y: 492, width: 560, height: 28)); recorder.isEditable = false; recorder.isSelectable = false
        recorder.recorded = { [weak self] shortcut in guard let self else { return }; self.store.shortcut = shortcut; self.refresh(); self.changed?() }; root.addSubview(recorder)
        method = NSPopUpButton(frame: NSRect(x: 28, y: 438, width: 560, height: 30)); method.addItems(withTitles: ["キーの組合せ（Carbon）", "修飾キー A：状態をポーリング", "修飾キー B：イベントを受信"]); method.target = self; method.action = #selector(methodChanged); root.addSubview(method)
        side = NSPopUpButton(frame: NSRect(x: 28, y: 396, width: 270, height: 30)); side.addItems(withTitles: ["左 Command", "右 Command", "左 Option", "右 Option", "左 Control", "右 Control", "左 Shift", "右 Shift"]); side.target = self; side.action = #selector(sideChanged); root.addSubview(side)
        note = label("", size: 12); note.frame = NSRect(x: 28, y: 348, width: 560, height: 40); note.maximumNumberOfLines = 2; root.addSubview(note)
        permission = ActionButton("入力監視の許可をリクエスト") { [weak self] in
            guard let self, self.store.method == .eventTap else { return }
            _ = CGRequestListenEventAccess(); self.refresh(); self.changed?()
        }; permission.frame = NSRect(x: 28, y: 308, width: 280, height: 30); root.addSubview(permission)
        #if DEBUG || TRIAL_DIAGNOSTICS
        text("診断", 262, 18)
        diagnosticLabel = label("", size: 12); diagnosticLabel.maximumNumberOfLines = 10; diagnosticLabel.frame = NSRect(x: 28, y: 70, width: 560, height: 188); root.addSubview(diagnosticLabel)
        let copy = ActionButton("テキストをコピー") { [weak self] in let text = self?.diagnosticText?() ?? Diagnostics().text; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }; copy.frame = NSRect(x: 28, y: 28, width: 180, height: 30); root.addSubview(copy)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in guard let self else { return }; self.diagnosticLabel.stringValue = self.diagnosticText?() ?? Diagnostics().text }
        diagnosticLabel.stringValue = Diagnostics().text
        #endif
        refresh()
    }
    func refresh() {
        method.selectItem(at: InputMethod.allCases.firstIndex(of: store.method) ?? 0)
        side.selectItem(at: ModifierSide.allCases.firstIndex(of: store.side) ?? 0); side.isEnabled = store.method != .carbon
        let s = store.shortcut
        let special: [UInt32: String] = [45: "N", 80: "F19"]
        recorder.stringValue = "\(s.modifiers & 0x1000 != 0 ? "⌃" : "")\(s.modifiers & 0x0800 != 0 ? "⌥" : "")\(s.modifiers & 0x0100 != 0 ? "⌘" : "")\(s.modifiers & 0x0200 != 0 ? "⇧" : "") \(special[s.keyCode] ?? "キー \(s.keyCode)")"
        permission.isHidden = store.method != .eventTap
        note.stringValue = store.method == .eventTap ? (CGPreflightListenEventAccess() ? "入力監視：許可済み" : "方式 B は入力監視の許可が必要です。未許可時は押すたびに開閉します。") : ""
    }
    @objc private func methodChanged() { store.method = InputMethod.allCases[method.indexOfSelectedItem]; refresh(); changed?() }
    @objc private func sideChanged() { store.side = ModifierSide.allCases[side.indexOfSelectedItem]; changed?() }
    func show() { refresh(); window.center(); window.makeKeyAndOrderFront(nil) }
    deinit {
        #if DEBUG || TRIAL_DIAGNOSTICS
        timer?.invalidate()
        #endif
    }
}

#if DEBUG || TRIAL_DIAGNOSTICS
func processRSS() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
#endif
