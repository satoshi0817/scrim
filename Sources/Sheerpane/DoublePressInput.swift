import AppKit
import Carbon
import SheerpaneCore

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
final class DoublePressInput {
    var onEffect: ((DoublePressMachine.Effect) -> Void)?
    var onStatus: (() -> Void)?
    private let permission: GesturePermissionChecking
    private var machine = DoublePressMachine()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private(set) var available = false
    private(set) var secure = false
    init(permission: GesturePermissionChecking = AppGesturePermission()) { self.permission = permission }
    func start(settings: GestureSettings) {
        stop(); machine = DoublePressMachine(settings: settings)
        guard settings.enabled, AppGesturePermission.isIndependentApp else { onStatus?(); return }
        secure = IsSecureEventInputEnabled()
        // Status observation never creates or retries a tap.
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let next = IsSecureEventInputEnabled()
            if next != self.secure { self.secure = next; self.onEffect?(self.machine.cancel(.unavailable)); self.onStatus?() }
            if self.available && (!self.permission.isGranted() || self.tap.map({ !CGEvent.tapIsEnabled(tap: $0) }) == true) {
                self.disableTap(); self.onStatus?()
            }
        }
        guard permission.isGranted() else { onStatus?(); return }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DoublePressInput>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { owner.disableTap(); owner.onStatus?() }
            else { owner.receive(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
            self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            available = CGEvent.tapIsEnabled(tap: tap)
        }
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
    func stop() {
        timer?.invalidate(); timer = nil
        disableTap()
    }
    private func disableTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap { CFMachPortInvalidate(tap) }; tap = nil
        available = false; onEffect?(machine.cancel(.unavailable))
    }
    deinit { stop() }
}
