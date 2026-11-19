import AppKit
import SwiftUI
import ScrimCore
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
        let title = label("Scrim を使い始める", size: 26)
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

final class SettingsController: NSObject, NSWindowDelegate, ObservableObject {
    let store: SettingsStore
    let window: NSWindow
    private let tabs = NSTabViewController()
    var changed: (() -> Void)?
    var gestureChanged: (() -> Void)?
    var gestureAvailable: (() -> Bool)?
    var registerShortcut: ((Shortcut) -> HotkeyRegistrationStatus)?
    var shortcutCommitted: (() -> Void)?
    var dockChanged: (() -> Void)?
    var recordingBegan: (() -> Void)?
    var recordingCancelled: (() -> Void)?
    private(set) var recordingSession: ShortcutRecordingSession
    var isRecording: Bool { recordingSession.isActive }
    weak var embeddedWindow: NSWindow?
    private var presentationWindow: NSWindow { embeddedWindow ?? window }
    func finishEmbedded() {
        cancelRecording()
        closePermissionCard()
        embeddedWindow = nil
        store.finishFirstRunGuidance()
    }
    private var keyMonitor: Any?
    private var permissionWindow: NSWindow?
    private var permissionTimer: Timer?
    private var permissionPolicy: GesturePermissionPresentationPolicy
    private let permissionState: () -> Bool
    var permissionGranted: Bool { permissionState() }
    var monitoringActive: Bool { gestureAvailable?() ?? permissionGranted }
    var monitoringStatus: String {
        if !store.gesture.enabled { return "オフ" }
        if !permissionGranted { return "許可が必要です" }
        return monitoringActive ? "動作中" : "監視を開始できません"
    }
    func retryMonitoring() { gestureChanged?(); refresh() }
    var advanced = false { didSet { refresh() } }
    let loginModel: LoginItemSettingsModel
    var registrationStatus: HotkeyRegistrationStatus = .success { didSet { refresh() } }
    var shortcutPresentation: Trial2SettingsPresentation {
        Trial2SettingsPresentation(retainedShortcut: store.shortcut, registration: registrationStatus, isRecording: isRecording)
    }
    var shortcutFeedback: String? {
        if isRecording, let feedback = recordingSession.feedback { return feedback }
        return registrationStatus == .success ? nil : shortcutPresentation.errorLines.joined(separator: "\n")
    }
    #if DEBUG || TRIAL_DIAGNOSTICS
    var diagnosticText: (() -> String)?
    private var timer: Timer?
    var diagnostics: String { diagnosticText?() ?? Diagnostics().text }
    #endif

    init(store: SettingsStore, permissionState: @escaping () -> Bool = { AppGesturePermission().isGranted() },
         loginService: LoginItemService = MainAppLoginItemService()) {
        self.store = store; self.permissionState = permissionState
        loginModel = LoginItemSettingsModel(service: loginService)
        permissionPolicy = GesturePermissionPresentationPolicy(deferred: store.gesturePermissionDeferred)
        recordingSession = ShortcutRecordingSession(savedShortcut: store.shortcut)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.sharingType = store.hideFromScreenCapture ? .none : .readOnly
        window.title = "Scrim 設定"; window.isReleasedWhenClosed = false; window.delegate = self
        window.toolbarStyle = .preference
        tabs.tabStyle = .toolbar
        for page in NativeSettingsPage.allCases {
            let host = NSHostingController(rootView: NativeSettingsForm(controller: self, page: page))
            host.preferredContentSize = NSSize(width: 640, height: 540)
            let item = NSTabViewItem(viewController: host)
            item.label = page.title; item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
        window.setContentSize(NSSize(width: 640, height: 540))
        #if DEBUG || TRIAL_DIAGNOSTICS
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, self.window.isVisible, self.tabs.selectedTabViewItemIndex == NativeSettingsPage.allCases.count-1 else { return }
            self.refresh()
        }
        #endif
    }
    func refresh() { objectWillChange.send() }
    func previewAdvanced() { advanced = true; tabs.selectedTabViewItemIndex = 1 }
    func firstRunGuidance() { autoPresentPermission(.firstRun) }
    private func autoPresentPermission(_ trigger: GesturePermissionPresentationPolicy.Trigger) {
        if permissionPolicy.shouldPresent(trigger, granted: permissionState()) { presentGesturePermission() }
    }
    static func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func setAppearanceMode(_ mode: AppearanceMode) {
        store.appearanceMode = mode
        Self.applyAppearance(mode)
        refresh()
    }
    func setDockVisible(_ value: Bool) { store.dockVisible = value; dockChanged?(); refresh() }
    func setOverlayControlsVisible(_ value: Bool) { store.showsOverlayControls = value; changed?(); refresh() }
    func setLoginEnabled(_ value: Bool) { loginModel.setEnabled(value); refresh() }
    func setCaptureExclusion(_ value: Bool) { store.hideFromScreenCapture = value; window.sharingType = value ? .none : .readOnly; changed?(); refresh() }
    func setWeatherShowsHourly(_ value: Bool) { store.weatherShowsHourly = value; changed?(); refresh() }
    func setWebDisplayMode(_ value: WebDisplayMode) { store.webDisplayMode = value; changed?(); refresh() }
    func setAgendaResetsScrollOnOpen(_ value: Bool) { store.agendaResetsScrollOnOpen = value; changed?(); refresh() }
    func setPeekInteraction(_ value: Bool) { store.peekAllowsInteraction = value; changed?(); gestureChanged?(); refresh() }
    func setCalendarReturnsToToday(_ value: Bool) { store.calendarReturnsToToday = value; changed?(); refresh() }
    func setSameLayout(_ value: Bool) { store.sameLayoutOnAllDisplays = value; changed?(); refresh() }
    func updateGesture(_ update: (inout GestureSettings) -> Void) {
        let previous = store.gesture
        var gesture = previous; update(&gesture); store.gesture = gesture
        gestureChanged?(); refresh()
        if gesture.enabled && (!previous.enabled || previous.useFn != gesture.useFn) { autoPresentPermission(.gestureEnabled) }
    }
    func updateTiming(_ keyPath: WritableKeyPath<GestureSettings, Double>, value: Double) {
        guard value.isFinite, value > 0, value <= 2 else { refresh(); return }
        updateGesture { $0[keyPath: keyPath] = value }
    }
    func resetShortcut() { beginRecording(); receiveShortcut(.default) }
    func beginRecording(installMonitor: Bool = true) {
        cancelRecording(silent: true)
        recordingSession = ShortcutRecordingSession(savedShortcut: store.shortcut); recordingSession.begin()
        recordingBegan?(); refresh(); presentationWindow.makeFirstResponder(nil)
        guard installMonitor else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, self.presentationWindow.isKeyWindow, event.window === self.presentationWindow else { return event }
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
        refresh()
    }
    private func removeRecordingMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil
        presentationWindow.makeFirstResponder(nil)
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
        permissionWindow = card; card.isReleasedWhenClosed = false; card.title = "Scrim"
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
        presentationWindow.beginSheet(card)
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
        if let card = permissionWindow { card.sheetParent?.endSheet(card); card.close() }; permissionWindow = nil
    }
    func show() {
        window.contentViewController = tabs
        window.title = "Scrim 設定"
        refresh(); gestureChanged?()
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func showGuide() { show() }
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
