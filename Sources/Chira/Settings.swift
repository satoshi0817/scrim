import AppKit
import ChiraCore
#if DEBUG || TRIAL_DIAGNOSTICS
import Darwin
#endif

/// Shared by the real first-run window and previews. Permission is an injected action;
/// offscreen previews supply no action and cannot request access.
final class FirstRunGuideView: NSView {
    init(shortcut: Shortcut, method: InputMethod, requestPermission: (() -> Void)? = nil,
         openSettings: (() -> Void)? = nil, finish: (() -> Void)? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 400))
        wantsLayer = true; layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        let title = label("Chira を使い始める", size: 26)
        title.frame = NSRect(x: 28, y: 324, width: 564, height: 40); addSubview(title)
        let explanation = label("\(shortcut.displayString) を押している間だけ表示します。\n短く押すと固定して、ウェブパネルを操作できます。\nEsc・背景クリック・同じショートカットで閉じます。")
        explanation.maximumNumberOfLines = 3
        explanation.frame = NSRect(x: 28, y: 214, width: 564, height: 90); addSubview(explanation)
        let content = GuideContent(method: method)
        if content.showsPermissionNote {
            let note = label(content.permissionBlockText ?? "", size: 12)
            note.maximumNumberOfLines = 2; note.frame = NSRect(x: 28, y: 154, width: 564, height: 44); addSubview(note)
            let permission = ActionButton(GuideContent.permissionRequestTitle) { requestPermission?() }
            permission.frame = NSRect(x: 28, y: 112, width: 280, height: 30); addSubview(permission)
        }
        let settings = ActionButton("設定を開く") { openSettings?() }
        settings.frame = NSRect(x: 28, y: 28, width: 140, height: 32); addSubview(settings)
        let done = ActionButton("使い始める") { finish?() }
        done.frame = NSRect(x: 452, y: 28, width: 140, height: 32); addSubview(done)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class SettingsController: NSObject {
    let store: SettingsStore
    let window: NSWindow
    var changed: (() -> Void)?
    var registrationStatus: HotkeyRegistrationStatus = .success {
        didSet { refreshRegistrationAppearance() }
    }
    private let registrationLabel = label("", size: 12)
    private let guide = label("")
    private let modifierHint = label("修飾キーだけで使う場合に選べます（権限が必要）", size: 12)
    private var settingsContent: NSView?
    private let permissionState: () -> Bool
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
    init(store: SettingsStore, permissionState: @escaping () -> Bool = { CGPreflightListenEventAccess() }) {
        self.store = store; self.permissionState = permissionState
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Chira 設定"; window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 800)); root.wantsLayer = true; root.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor; window.contentView = root
        settingsContent = root
        func text(_ value: String, _ y: CGFloat, _ size: CGFloat = 14) { let v = label(value, size: size); v.frame = NSRect(x: 28, y: y, width: 560, height: 30); root.addSubview(v) }
        text("Chira", 742, 26)
        guide.frame = NSRect(x: 28, y: 702, width: 560, height: 30); root.addSubview(guide)
        text("固定中は Esc・背景クリック・同じショートカットで閉じます。", 674)
        text("ショートカット（欄を選択してキーを入力）", 626)
        recorder = ShortcutRecorder(frame: NSRect(x: 28, y: 592, width: 560, height: 28)); recorder.isEditable = false; recorder.isSelectable = false
        recorder.recorded = { [weak self] shortcut in guard let self else { return }; self.store.shortcut = shortcut; self.store.method = .carbon; self.refresh(); self.changed?() }; root.addSubview(recorder)
        method = NSPopUpButton(frame: NSRect(x: 28, y: 538, width: 560, height: 30)); method.addItems(withTitles: ["キーの組み合わせ", "修飾キー A：状態をポーリング", "修飾キー B：イベントを受信"]); method.target = self; method.action = #selector(methodChanged); root.addSubview(method)
        side = NSPopUpButton(frame: NSRect(x: 28, y: 496, width: 270, height: 30)); side.addItems(withTitles: ["左 Command", "右 Command", "左 Option", "右 Option", "左 Control", "右 Control", "左 Shift", "右 Shift"]); side.target = self; side.action = #selector(sideChanged); root.addSubview(side)
        modifierHint.frame = NSRect(x: 28, y: 496, width: 560, height: 30); modifierHint.textColor = .lightGray; root.addSubview(modifierHint)
        note = label("", size: 12); note.frame = NSRect(x: 28, y: 448, width: 560, height: 40); note.maximumNumberOfLines = 2; root.addSubview(note)
        permission = ActionButton(GuideContent.permissionRequestTitle) { [weak self] in self?.requestModifierPermission() }
        permission.frame = NSRect(x: 28, y: 408, width: 280, height: 30); root.addSubview(permission)
        registrationLabel.frame = NSRect(x: 28, y: 520, width: 560, height: 64)
        registrationLabel.maximumNumberOfLines = 4; registrationLabel.lineBreakMode = .byWordWrapping
        registrationLabel.textColor = .systemOrange; root.addSubview(registrationLabel)
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
        side.selectItem(at: ModifierSide.allCases.firstIndex(of: store.side) ?? 0)
        side.isHidden = store.method == .carbon; modifierHint.isHidden = store.method != .carbon
        recorder.stringValue = store.shortcut.displayString
        guide.stringValue = "\(store.shortcut.displayString) を押している間だけ表示。短く押すと固定します。"
        let content = GuideContent(method: store.method)
        permission.isHidden = !content.showsPermissionNote; note.isHidden = !content.showsPermissionNote
        note.stringValue = content.showsPermissionNote ? (permissionState() ? GuideContent.permissionGrantedText : content.permissionBlockText ?? "") : ""
        refreshRegistrationAppearance()
    }
    private func refreshRegistrationAppearance() {
        let failed = registrationStatus.message != nil
        registrationLabel.stringValue = registrationStatus.message ?? ""; registrationLabel.isHidden = !failed
        recorder.wantsLayer = true
        recorder.layer?.cornerRadius = 4
        recorder.layer?.borderWidth = failed ? 2 : 0
        recorder.layer?.borderColor = failed ? NSColor.systemOrange.cgColor : nil
        // Leave an eight-point gap below the recorder; reserve error space only when used.
        let shift: CGFloat = failed ? 64 : 0
        method.frame.origin.y = 538-shift; side.frame.origin.y = 496-shift; modifierHint.frame.origin.y = 496-shift
        note.frame.origin.y = 448-shift; permission.frame.origin.y = 408-shift
    }
    @objc private func methodChanged() { store.method = InputMethod.allCases[method.indexOfSelectedItem]; refresh(); changed?() }
    @objc private func sideChanged() { store.side = ModifierSide.allCases[side.indexOfSelectedItem]; changed?() }
    private func requestModifierPermission() {
        guard GuideContent(method: store.method).showsPermissionNote else { return }
        if store.method == .flagsPoll {
            // A does not request access. Select B first; its explicit button can then request.
            store.method = .eventTap; refresh(); changed?(); show(); return
        }
        guard store.method == .eventTap else { return }
        _ = CGRequestListenEventAccess(); refresh(); changed?()
    }
    func show() {
        window.title = "Chira 設定"; window.setContentSize(NSSize(width: 620, height: 800))
        settingsContent?.setFrameSize(NSSize(width: 620, height: 800))
        window.contentView = settingsContent; refresh(); window.center(); window.makeKeyAndOrderFront(nil)
    }
    func showGuide() {
        let content = FirstRunGuideView(shortcut: store.shortcut, method: store.method, requestPermission: { [weak self] in
            self?.requestModifierPermission()
        }, openSettings: { [weak self] in self?.show() }, finish: { [weak self] in self?.window.close() })
        window.title = "Chira はじめに"; window.setContentSize(content.frame.size); window.contentView = content
        window.center(); window.makeKeyAndOrderFront(nil)
    }
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
