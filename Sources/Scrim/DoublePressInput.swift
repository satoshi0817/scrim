import AppKit
import Carbon
import ScrimCore

/// Direct CLI launches (including previews) cannot use host-inherited TCC grants.
struct AppGesturePermission: GesturePermissionChecking {
    static var isIndependentApp: Bool {
        GestureIdentityPolicy.mayInspect(bundleIdentifier: Bundle.main.bundleIdentifier, isAppBundle: Bundle.main.bundleURL.pathExtension == "app", parentPID: getppid())
    }
    func isGranted() -> Bool { Self.isIndependentApp && CGPreflightListenEventAccess() }
    func requestFromAllowButton() {
        guard Self.isIndependentApp else { return }
        _ = CGRequestListenEventAccess()
    }
}
protocol GestureEventTap: AnyObject {
    var healthy: Bool { get }
    func connect(receive: @escaping (CGEventType, CGEvent) -> Void, disabled: @escaping () -> Void)
    func disconnect()
}

/// One OS-global, listen-only tap. A created tap is healthy only if the OS
/// reports it enabled with every requested event type still present.
final class SystemGestureEventTap: GestureEventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var receive: ((CGEventType, CGEvent) -> Void)?
    private var disabled: (() -> Void)?
    var healthy: Bool {
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else { return false }
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return false }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        let result = taps.withUnsafeMutableBufferPointer { CGGetEventTapList(count, $0.baseAddress, &count) }
        guard result == .success else { return false }
        return taps.prefix(Int(count)).contains { $0.tappingProcess == getpid() && $0.enabled && ($0.eventsOfInterest & DoublePressInput.requiredMask) == DoublePressInput.requiredMask }
    }
    func connect(receive: @escaping (CGEventType, CGEvent) -> Void, disabled: @escaping () -> Void) {
        disconnect(); self.receive = receive; self.disabled = disabled
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: DoublePressInput.requiredMask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<SystemGestureEventTap>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { owner.disabled?() }
                else { owner.receive?(type, event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
            self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    func disconnect() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap { CFMachPortInvalidate(tap) }; tap = nil
        receive = nil; disabled = nil
    }
    deinit { disconnect() }
}

final class DoublePressInput {
    static let eventTypes: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    static let requiredMask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    var onEffect: ((DoublePressMachine.Effect) -> Void)?
    var onStatus: (() -> Void)?
    private let permission: GesturePermissionChecking
    private let eventTap: GestureEventTap
    private let independentApp: () -> Bool
    private let secureInput: () -> Bool
    private let clock: () -> TimeInterval
    private var machine = DoublePressMachine()
    private var timer: Timer?
    private var retryAfter: TimeInterval = 0
    private var running = false
    private(set) var available = false
    private(set) var secure = false
    init(permission: GesturePermissionChecking = AppGesturePermission(), eventTap: GestureEventTap = SystemGestureEventTap(),
         independentApp: @escaping () -> Bool = { AppGesturePermission.isIndependentApp },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.permission = permission; self.eventTap = eventTap; self.independentApp = independentApp
        self.secureInput = secureInput; self.clock = clock
    }
    func start(settings: GestureSettings, installTimer: Bool = true, allowsPeekInteraction: Bool = true) {
        stop(); machine = DoublePressMachine(settings: settings, allowsPeekInteraction: allowsPeekInteraction)
        guard settings.enabled, independentApp() else { onStatus?(); return }
        running = true; secure = secureInput()
        if installTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
        }
        connect()
    }
    /// Permission and mask checks run at most once a second; secure input stays
    /// responsive. Reconnection never requests a permission or resets TCC.
    func poll() {
        guard running else { return }
        let next = secureInput()
        if next != secure { secure = next; onEffect?(machine.cancel(.unavailable)); onStatus?() }
        guard clock() >= retryAfter else { return }
        retryAfter = clock()+1
        let granted = permission.isGranted()
        if available && (!granted || !eventTap.healthy) { disableTap(); onStatus?() }
        if granted && !available { connect() }
    }
    private func connect() {
        retryAfter = clock()+1
        guard independentApp(), permission.isGranted() else { onStatus?(); return }
        eventTap.connect(receive: { [weak self] type, event in self?.receive(type: type, event: event) }, disabled: { [weak self] in
            guard let self else { return }
            self.disableTap(); self.retryAfter = self.clock()+1; self.onStatus?()
        })
        available = eventTap.healthy
        if !available { disableTap() }
        onStatus?()
    }
    private func receive(type: CGEventType, event: CGEvent) {
        guard !secure else { return }
        if type != .flagsChanged { onEffect?(machine.interrupt(key: type == .keyDown)); return }
        let raw = event.flags.rawValue
        let sides = ModifierSide.pressed(rawFlags: raw)
        let other = !sides.subtracting([.leftCommand, .rightCommand]).isEmpty || !event.flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty
        let mouse = (0..<32).contains { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) }
        let input = GestureSnapshot(left: sides.contains(.leftCommand), right: sides.contains(.rightCommand), fn: event.flags.contains(.maskSecondaryFn), otherModifiers: other, mouseDown: mouse)
        onEffect?(machine.update(input, at: Double(event.timestamp) / 1_000_000_000))
    }
    func cancelPendingGesture() { _ = machine.cancel(.unavailable) }
    func stop() {
        timer?.invalidate(); timer = nil; running = false; secure = false; retryAfter = 0
        disableTap()
    }
    private func disableTap() {
        eventTap.disconnect(); available = false; onEffect?(machine.cancel(.unavailable))
    }
    deinit { stop() }
}
