import AppKit
import SheerpaneCore
#if DEBUG || TRIAL_DIAGNOSTICS
import Darwin
#endif

/// Legacy guide, currently used only by explicit review fixtures: showGuide has no callers.
/// Shipping first launch opens the full settings view. Offscreen fixtures inject no actions.
final class FirstRunGuideView: NSView {
    init(shortcut: Shortcut, method: InputMethod, requestPermission: (() -> Void)? = nil,
         openSettings: (() -> Void)? = nil, finish: (() -> Void)? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 400))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let title = label("Sheerpane を使い始める", size: 26)
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
    var gestureChanged: (() -> Void)?
    var gestureAvailable: (() -> Bool)?
    private var gestureView: GestureSettingsView!
    private var permissionWindow: NSWindow?
    private var permissionTimer: Timer?
    private var permissionPolicy: GesturePermissionPresentationPolicy
    private var upperGestureViews: [(NSView, CGFloat)] = []
    func firstRunGuidance() { autoPresentPermission(.firstRun) }
    private func autoPresentPermission(_ trigger: GesturePermissionPresentationPolicy.Trigger) {
        if permissionPolicy.shouldPresent(trigger, granted: permissionState()) { presentGesturePermission() }
    }
    func previewAdvanced() { gestureView.expanded = true }
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
    let loginModel: LoginItemSettingsModel
    private var loginButton: NSButton!
    private let loginHelper = label(LoginItemSettingsModel.approvalText, size: 12)
    private let loginError = label("", size: 12)
    private var loginSettingsButton: ActionButton!
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
    init(store: SettingsStore, permissionState: @escaping () -> Bool = { AppGesturePermission().isGranted() },
         loginService: LoginItemService = MainAppLoginItemService()) {
        loginModel = LoginItemSettingsModel(service: loginService)
        self.store = store; self.permissionState = permissionState
        permissionPolicy = GesturePermissionPresentationPolicy(deferred: store.gesturePermissionDeferred)
        recordingSession = ShortcutRecordingSession(savedShortcut: store.shortcut)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.title = "Sheerpane 設定"; window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 800)); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; window.contentView = root
        settingsContent = root
        func text(_ value: String, _ y: CGFloat, _ size: CGFloat = 14) { let v = label(value, size: size); v.textColor = .labelColor; v.frame = NSRect(x: 28, y: y, width: 560, height: 30); root.addSubview(v) }
        text("Sheerpane", 742, 26)
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
        dockButton = NSButton(checkboxWithTitle: "Dock に Sheerpane を表示", target: self, action: #selector(toggleDock))
        dockButton.frame = NSRect(x: 28, y: 252, width: 420, height: 26); root.addSubview(dockButton)
        #if DEBUG || TRIAL_DIAGNOSTICS
        text("診断", 212, 18)
        diagnosticLabel = label("", size: 12); diagnosticLabel.maximumNumberOfLines = 10; diagnosticLabel.frame = NSRect(x: 28, y: 70, width: 560, height: 138); root.addSubview(diagnosticLabel)
        diagnosticLabel.textColor = .labelColor
        let copy = ActionButton("テキストをコピー") { [weak self] in let text = self?.diagnosticText?() ?? Diagnostics().text; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }; copy.frame = NSRect(x: 28, y: 28, width: 180, height: 30); root.addSubview(copy)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in guard let self else { return }; self.diagnosticLabel.stringValue = self.diagnosticText?() ?? Diagnostics().text }
        diagnosticLabel.stringValue = Diagnostics().text
        #endif
        upperGestureViews = root.subviews.filter { $0.frame.minY >= 590 }.map { ($0, $0.frame.minY) }
        loginButton = NSButton(checkboxWithTitle: LoginItemSettingsModel.title, target: self, action: #selector(toggleLogin))
        loginButton.frame = NSRect(x: 28, y: 0, width: 560, height: 26); root.addSubview(loginButton)
        loginHelper.textColor = .secondaryLabelColor
        loginHelper.frame = NSRect(x: 48, y: 326, width: 540, height: 22); root.addSubview(loginHelper)
        loginSettingsButton = ActionButton(LoginItemSettingsModel.settingsTitle) { [weak self] in self?.loginModel.openSettings() }
        loginSettingsButton.frame = NSRect(x: 48, y: 292, width: 200, height: 28); root.addSubview(loginSettingsButton)
        loginError.textColor = .systemRed
        loginError.alignment = .left
        loginError.usesSingleLineMode = false; loginError.maximumNumberOfLines = 0
        loginError.lineBreakMode = .byWordWrapping; loginError.cell?.wraps = true
        loginError.frame = NSRect(x: 48, y: 326, width: 540, height: 22); root.addSubview(loginError)
        gestureView = GestureSettingsView(store: store); root.addSubview(gestureView)
        gestureView.changed = { [weak self] in self?.gestureChanged?(); self?.refresh() }
        gestureView.permissionRequested = { [weak self] in self?.autoPresentPermission(.manual) }
        gestureView.gestureEnabled = { [weak self] in self?.autoPresentPermission(.gestureEnabled) }
        gestureView.layoutChanged = { [weak self] in self?.refresh() }
        refresh()
    }
    func refresh() {
        let presentation = Trial2SettingsPresentation(retainedShortcut: store.shortcut, registration: registrationStatus, isRecording: isRecording)
        method.selectItem(at: InputMethod.allCases.firstIndex(of: store.method) ?? 0)
        side.selectItem(at: ModifierSide.allCases.firstIndex(of: store.side) ?? 0)
        method.isHidden = !presentation.showsModifierOnlyControls
        side.isHidden = !presentation.showsModifierOnlyControls; modifierHint.isHidden = !presentation.showsModifierOnlyControls
        recorder.stringValue = presentation.recorderFieldText
        guide.stringValue = store.gesture.useFn ? "fn を2回押して、2回目を押したまま" : GestureCopy.action
        guide.font = .systemFont(ofSize: 23)
        dockButton.state = store.dockVisible ? .on : .off
        loginButton.state = loginModel.isOn ? .on : .off
        loginHelper.isHidden = !loginModel.showsApproval
        loginSettingsButton.isHidden = !loginModel.showsSettings
        loginError.stringValue = loginModel.errorText ?? ""
        loginError.isHidden = loginModel.errorText == nil
        method.isEnabled = !isRecording; side.isEnabled = !isRecording
        changeButton.title = presentation.changeButtonTitle
        layoutShortcutControls()
        recorder.recording = isRecording
        let content = GuideContent(method: store.method)
        permission.isHidden = !presentation.showsModifierOnlyControls || !content.showsPermissionNote
        note.isHidden = permission.isHidden
        permission.isEnabled = !isRecording
        note.stringValue = !note.isHidden ? (permissionState() ? GuideContent.permissionGrantedText : content.permissionBlockText ?? "") : ""
        method.isHidden = true; side.isHidden = true; modifierHint.isHidden = true; permission.isHidden = true; note.isHidden = true
        gestureView?.isHidden = isRecording || registrationStatus != .success
        gestureView?.permissionGranted = permissionState()
        layoutLoginGroup()
        refreshRegistrationAppearance()
    }
    private func layoutLoginGroup() {
        // Lay out downward from the last visible gesture line, not its empty view bounds.
        let gestureBottom = gestureView.subviews.filter { !$0.isHidden }.map { $0.frame.minY }.min() ?? 0
        // Remove the unused bottom bounds too, so that this view cannot intercept
        // clicks on the checkbox group placed in that formerly empty region.
        if gestureBottom > 0 {
            gestureView.subviews.forEach { $0.frame.origin.y -= gestureBottom }
            gestureView.frame.size.height -= gestureBottom
        }
        gestureView.frame.origin = NSPoint(x: 28, y: 580 - gestureView.frame.height)
        var cursor = gestureView.frame.minY - 20
        loginButton.frame.origin.y = cursor - loginButton.frame.height
        cursor = loginButton.frame.minY

        let titleRect = loginButton.cell?.titleRect(forBounds: loginButton.bounds) ?? loginButton.bounds
        let accessoryX = loginButton.frame.minX + titleRect.minX
        let accessoryWidth = 588 - accessoryX
        for text in [loginHelper, loginError] where !text.isHidden {
            let height = ceil(text.cell?.cellSize(forBounds:
                NSRect(x: 0, y: 0, width: accessoryWidth, height: CGFloat.greatestFiniteMagnitude)).height ?? 0)
            cursor -= 6 + height
            text.frame = NSRect(x: accessoryX, y: cursor, width: accessoryWidth, height: height)
        }
        if !loginSettingsButton.isHidden {
            cursor -= 6 + 28
            loginSettingsButton.frame = NSRect(x: accessoryX, y: cursor, width: 200, height: 28)
        }
        cursor -= 6 + dockButton.frame.height
        dockButton.frame.origin.y = cursor

        // Keep the bottom margin and diagnostics intact while extra rows grow downward
        // in window coordinates. Hidden accessories contribute no height or spacing.
        let growth = 252 - cursor
        upperGestureViews.forEach { $0.0.frame.origin.y = $0.1 + growth }
        for view in [gestureView!, loginButton!, loginHelper, loginError, loginSettingsButton!, dockButton!] where !view.isHidden {
            view.frame.origin.y += growth
        }
        let size = NSSize(width: 620, height: 800 + growth)
        settingsContent?.setFrameSize(size)
        window.setContentSize(size)
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
        recorder.layer?.borderWidth = CGFloat(presentation.recorderWarningBorderWidth)
        recorder.layer?.borderColor = nil
        // Fit the wrapped copy so the helper follows text, not a reserved empty block.
        let errorTop: CGFloat = recorder.frame.minY - 8
        let errorHeight = ceil(registrationLabel.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: 560, height: CGFloat.greatestFiniteMagnitude)).height ?? 0)
        registrationLabel.frame = NSRect(x: 28, y: errorTop-errorHeight, width: 560, height: errorHeight)
        let helperTop = errorTop - CGFloat(Trial2SettingsPresentation.retainedHelperTopOffset(errorHeight: Double(errorHeight)))
        let helperHeight = ceil(retainedShortcutLabel.cell?.cellSize.height ?? 18)
        retainedShortcutLabel.frame = NSRect(x: 28, y: helperTop-helperHeight, width: 560, height: helperHeight)
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
    @objc private func toggleLogin() { loginModel.setEnabled(loginButton.state == .on); refresh() }
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
    func windowWillClose(_ notification: Notification) {
        store.finishFirstRunGuidance()
        cancelRecording(); closePermissionCard()
    }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func windowDidResignKey(_ notification: Notification) { if isRecording { cancelRecording() } }
    private func requestModifierPermission() { presentGesturePermission() }
    func presentGesturePermission() {
        let initiallyGranted = permissionState()
        let unavailable = initiallyGranted && gestureAvailable?() == false
        guard (!initiallyGranted || unavailable), permissionWindow == nil else { return }
        let card = NSWindow(contentRect: NSRect(x: 0, y: 0, width: GestureSettingsPresentation.permissionCardWidth, height: GestureSettingsPresentation.permissionCardHeight), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        permissionWindow = card; card.isReleasedWhenClosed = false; card.title = "Sheerpane"
        func render(_ state: GesturePermissionState) {
            card.contentView = GesturePermissionView(state: state, unavailable: unavailable, allow: { [weak self] in
                guard let self else { return }; self.store.gesturePermissionAsked = true
                AppGesturePermission().requestFromAllowButton()
                render(self.permissionState() ? .granted : .denied)
            }, later: { [weak self] in
                guard let self else { return }; self.permissionPolicy.later(); self.store.gesturePermissionDeferred = true; self.closePermissionCard()
            }, openSettings: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            })
        }
        render(store.gesturePermissionAsked || unavailable ? .denied : .unasked)
        window.beginSheet(card)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !card.isVisible { self.closePermissionCard(); return }
            if !initiallyGranted && self.permissionState() {
                self.permissionTimer?.invalidate(); self.permissionTimer = nil
                render(.granted); self.gestureChanged?(); self.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.closePermissionCard() }
            }
        }
    }
    private func closePermissionCard() {
        permissionTimer?.invalidate(); permissionTimer = nil
        if let card = permissionWindow { window.endSheet(card); card.close() }; permissionWindow = nil
    }
    func show() {
        window.title = "Sheerpane 設定"
        window.contentView = settingsContent; refresh(); gestureChanged?(); bringSettingsToFront()
        // Opening Settings alone never auto-presents the card.
    }
    func showGuide() {
        let content = FirstRunGuideView(shortcut: store.shortcut, method: store.method, requestPermission: { [weak self] in
            self?.requestModifierPermission()
        }, openSettings: { [weak self] in self?.show() }, finish: { [weak self] in self?.window.close() })
        window.title = "Sheerpane はじめに"; window.setContentSize(content.frame.size); window.contentView = content
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
