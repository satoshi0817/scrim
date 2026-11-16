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
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let title = label("Chira を使い始める", size: 26)
        title.frame = NSRect(x: 28, y: 324, width: 564, height: 40); addSubview(title)
        let explanation = label(EntryState(shortcut: shortcut).guideText + "\n短く押すと固定して、ウェブパネルを操作できます。\nEsc・背景クリック・同じショートカットで閉じます。")
        explanation.maximumNumberOfLines = 4
        explanation.frame = NSRect(x: 28, y: 204, width: 564, height: 108); addSubview(explanation)
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
        for case let text as NSTextField in subviews { text.textColor = .labelColor }
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class SettingsController: NSObject, NSWindowDelegate {
    let store: SettingsStore
    let window: NSWindow
    var changed: (() -> Void)?
    var registerShortcut: ((Shortcut) -> HotkeyRegistrationStatus)?
    var shortcutCommitted: (() -> Void)?
    var dockChanged: (() -> Void)?
    var recordingBegan: (() -> Void)?
    var recordingCancelled: (() -> Void)?
    private(set) var recordingSession: ShortcutRecordingSession
    var isRecording: Bool { recordingSession.isActive }
    private var keyMonitor: Any?
    private var changeButton: ActionButton!
    private var defaultButton: ActionButton!
    private var dockButton: NSButton!
    var registrationStatus: HotkeyRegistrationStatus = .success {
        didSet { refreshRegistrationAppearance() }
    }
    private let registrationLabel = label("", size: 12)
    private let retainedShortcutLabel = label("", size: 12)
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
        recordingSession = ShortcutRecordingSession(savedShortcut: store.shortcut)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.title = "Chira 設定"; window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 800)); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; window.contentView = root
        settingsContent = root
        func text(_ value: String, _ y: CGFloat, _ size: CGFloat = 14) { let v = label(value, size: size); v.textColor = .labelColor; v.frame = NSRect(x: 28, y: y, width: 560, height: 30); root.addSubview(v) }
        text("Chira", 742, 26)
        guide.frame = NSRect(x: 28, y: 690, width: 560, height: 50); guide.maximumNumberOfLines = 2; root.addSubview(guide)
        guide.textColor = .labelColor
        text("固定中は Esc・背景クリック・同じショートカットで閉じます。", 674)
        text("ショートカット（変更 → 組み合わせを押す・Esc でキャンセル）", 626)
        recorder = ShortcutRecorder(frame: NSRect(x: 28, y: 592, width: 300, height: 28)); recorder.isEditable = false; recorder.isSelectable = false
        root.addSubview(recorder)
        changeButton = ActionButton("変更") { [weak self] in guard let self else { return }; if self.isRecording { self.cancelRecording() } else { self.beginRecording() } }
        changeButton.frame = NSRect(x: 340, y: 592, width: 124, height: 28); root.addSubview(changeButton)
        defaultButton = ActionButton("既定に戻す") { [weak self] in self?.beginRecording(); self?.receiveShortcut(.default) }
        defaultButton.frame = NSRect(x: 476, y: 592, width: 112, height: 28); root.addSubview(defaultButton)
        method = NSPopUpButton(frame: NSRect(x: 28, y: 538, width: 560, height: 30)); method.addItems(withTitles: ["キーの組み合わせ", "修飾キー A：状態をポーリング", "修飾キー B：イベントを受信"]); method.target = self; method.action = #selector(methodChanged); root.addSubview(method)
        side = NSPopUpButton(frame: NSRect(x: 28, y: 496, width: 270, height: 30)); side.addItems(withTitles: ["左 Command", "右 Command", "左 Option", "右 Option", "左 Control", "右 Control", "左 Shift", "右 Shift"]); side.target = self; side.action = #selector(sideChanged); root.addSubview(side)
        modifierHint.frame = NSRect(x: 28, y: 496, width: 560, height: 30); modifierHint.textColor = .secondaryLabelColor; root.addSubview(modifierHint)
        note = label("", size: 12); note.frame = NSRect(x: 28, y: 448, width: 560, height: 40); note.maximumNumberOfLines = 2; root.addSubview(note)
        note.textColor = .secondaryLabelColor
        permission = ActionButton(GuideContent.permissionRequestTitle) { [weak self] in self?.requestModifierPermission() }
        permission.frame = NSRect(x: 28, y: 408, width: 280, height: 30); root.addSubview(permission)
        registrationLabel.frame = NSRect(x: 28, y: 504, width: 560, height: 80)
        registrationLabel.maximumNumberOfLines = 4; registrationLabel.lineBreakMode = .byWordWrapping
        registrationLabel.textColor = .systemOrange; root.addSubview(registrationLabel)
        retainedShortcutLabel.frame = NSRect(x: 28, y: 474, width: 560, height: 24)
        retainedShortcutLabel.textColor = .secondaryLabelColor; root.addSubview(retainedShortcutLabel)
        dockButton = NSButton(checkboxWithTitle: "Dock に Chira を表示", target: self, action: #selector(toggleDock))
        dockButton.frame = NSRect(x: 28, y: 310, width: 420, height: 26); root.addSubview(dockButton)
        #if DEBUG || TRIAL_DIAGNOSTICS
        text("診断", 262, 18)
        diagnosticLabel = label("", size: 12); diagnosticLabel.maximumNumberOfLines = 10; diagnosticLabel.frame = NSRect(x: 28, y: 70, width: 560, height: 188); root.addSubview(diagnosticLabel)
        diagnosticLabel.textColor = .labelColor
        let copy = ActionButton("テキストをコピー") { [weak self] in let text = self?.diagnosticText?() ?? Diagnostics().text; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }; copy.frame = NSRect(x: 28, y: 28, width: 180, height: 30); root.addSubview(copy)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in guard let self else { return }; self.diagnosticLabel.stringValue = self.diagnosticText?() ?? Diagnostics().text }
        diagnosticLabel.stringValue = Diagnostics().text
        #endif
        refresh()
    }
    func refresh() {
        let presentation = Trial2SettingsPresentation(retainedShortcut: store.shortcut, registration: registrationStatus, isRecording: isRecording)
        method.selectItem(at: InputMethod.allCases.firstIndex(of: store.method) ?? 0)
        side.selectItem(at: ModifierSide.allCases.firstIndex(of: store.side) ?? 0)
        method.isHidden = !presentation.showsModifierOnlyControls
        side.isHidden = !presentation.showsModifierOnlyControls; modifierHint.isHidden = !presentation.showsModifierOnlyControls
        recorder.stringValue = presentation.recorderFieldText
        guide.stringValue = EntryState(shortcut: store.shortcut).guideText
        dockButton.state = store.dockVisible ? .on : .off
        method.isEnabled = !isRecording; side.isEnabled = !isRecording
        changeButton.title = presentation.changeButtonTitle
        layoutShortcutControls()
        recorder.recording = isRecording
        let content = GuideContent(method: store.method)
        permission.isHidden = !presentation.showsModifierOnlyControls || !content.showsPermissionNote
        note.isHidden = permission.isHidden
        permission.isEnabled = !isRecording
        note.stringValue = !note.isHidden ? (permissionState() ? GuideContent.permissionGrantedText : content.permissionBlockText ?? "") : ""
        refreshRegistrationAppearance()
    }
    private func refreshRegistrationAppearance() {
        let presentation = Trial2SettingsPresentation(retainedShortcut: store.shortcut, registration: registrationStatus, isRecording: isRecording)
        let failed = registrationStatus != .success
        let isValidationFeedback = recordingSession.phase == .recording && recordingSession.feedback != nil
            && recordingSession.feedback != RegistrationFeedback.message(registrationStatus)
        let feedback = failed && !isValidationFeedback ? presentation.errorLines.joined(separator: "\n") : recordingSession.feedback
        let text = isRecording ? "記録中 — Esc またはキャンセルで終了します。\n" + (feedback ?? "Control・Option・Command と通常のキーを押してください。") : feedback ?? ""
        registrationLabel.stringValue = text; registrationLabel.isHidden = text.isEmpty
        recorder.stringValue = presentation.recorderFieldText
        retainedShortcutLabel.stringValue = presentation.retainedHelperLine ?? ""
        retainedShortcutLabel.isHidden = presentation.retainedHelperLine == nil
        recorder.wantsLayer = true
        recorder.layer?.cornerRadius = 4
        recorder.layer?.borderWidth = failed ? 2 : 0
        recorder.layer?.borderColor = failed ? NSColor.systemOrange.cgColor : nil
        // Leave an eight-point gap below the recorder; reserve error space only when used.
        let shift: CGFloat = text.isEmpty ? 0 : 64
        method.frame.origin.y = 538-shift; side.frame.origin.y = 496-shift; modifierHint.frame.origin.y = 496-shift
        note.frame.origin.y = 448-shift; permission.frame.origin.y = 408-shift
    }
    private func layoutShortcutControls() {
        // Include native bezel padding as well as a minimum large enough for the
        // full Japanese cancel label. Allocate remaining space to the saved key.
        changeButton.sizeToFit(); defaultButton.sizeToFit()
        let changeWidth = max(CGFloat(Trial2SettingsPresentation.minimumChangeButtonWidth), changeButton.frame.width + 8)
        let defaultWidth = max(CGFloat(Trial2SettingsPresentation.minimumDefaultButtonWidth), defaultButton.frame.width + 8)
        let fieldWidth = 560-changeWidth-defaultWidth-24
        recorder.frame = NSRect(x: 28, y: 592, width: fieldWidth, height: 28)
        changeButton.frame = NSRect(x: recorder.frame.maxX+12, y: 592, width: changeWidth, height: 28)
        defaultButton.frame = NSRect(x: changeButton.frame.maxX+12, y: 592, width: defaultWidth, height: 28)
    }
    @objc private func methodChanged() { store.method = InputMethod.allCases[method.indexOfSelectedItem]; refresh(); changed?() }
    @objc private func sideChanged() { store.side = ModifierSide.allCases[side.indexOfSelectedItem]; changed?() }
    @objc private func toggleDock() { store.dockVisible = dockButton.state == .on; dockChanged?() }
    func beginRecording(installMonitor: Bool = true) {
        cancelRecording(silent: true)
        recordingSession = ShortcutRecordingSession(savedShortcut: store.shortcut); recordingSession.begin()
        recordingBegan?(); refresh(); window.makeFirstResponder(recorder)
        guard installMonitor else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, self.window.isKeyWindow, event.window === self.window else { return event }
            if event.keyCode == 53 { self.cancelRecording(); return nil }
            guard !event.isARepeat else { return nil }
            var flags: UInt32 = 0
            if event.modifierFlags.contains(.control) { flags |= 0x1000 }
            if event.modifierFlags.contains(.option) { flags |= 0x0800 }
            if event.modifierFlags.contains(.command) { flags |= 0x0100 }
            if event.modifierFlags.contains(.shift) { flags |= 0x0200 }
            self.receiveShortcut(Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags))
            return nil
        }
    }
    func receiveShortcut(_ candidate: Shortcut) {
        guard recordingSession.submit(candidate) else { refresh(); return }
        let result = registerShortcut?(candidate)
        guard let result else { cancelRecording(); return }
        if let confirmed = recordingSession.resolve(result) {
            store.shortcut = confirmed; store.method = .carbon
            removeRecordingMonitor(); shortcutCommitted?()
        }
        refresh()
    }
    func cancelRecording(silent: Bool = false) {
        let wasActive = isRecording
        removeRecordingMonitor()
        if silent { recordingSession = ShortcutRecordingSession(savedShortcut: store.shortcut) }
        else if isRecording { recordingSession.cancel() }
        if wasActive { recordingCancelled?() }
        if recorder != nil { refresh() }
    }
    private func removeRecordingMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil; recorder?.recording = false
        if window.firstResponder === recorder { window.makeFirstResponder(nil) }
    }
    func windowWillClose(_ notification: Notification) { cancelRecording() }
    func windowDidResignKey(_ notification: Notification) { if isRecording { cancelRecording() } }
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
        window.contentView = settingsContent; refresh(); bringSettingsToFront()
    }
    func showGuide() {
        let content = FirstRunGuideView(shortcut: store.shortcut, method: store.method, requestPermission: { [weak self] in
            self?.requestModifierPermission()
        }, openSettings: { [weak self] in self?.show() }, finish: { [weak self] in self?.window.close() })
        window.title = "Chira はじめに"; window.setContentSize(content.frame.size); window.contentView = content
        bringSettingsToFront()
    }
    private func bringSettingsToFront() {
        window.center()
        // Activation is restricted to this settings window, never the overlay.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
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
