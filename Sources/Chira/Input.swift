import AppKit
import Carbon
import ChiraCore

private let hotkeyCallback: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x43485241 else { return OSStatus(eventNotHandledErr) }
    let input = Unmanaged<InputController>.fromOpaque(context).takeUnretainedValue()
    input.edge(GetEventKind(event) == UInt32(kEventHotKeyPressed), source: .carbon)
    return noErr
}
enum InputOrigin { case carbon, flagsPoll, eventTap, none }
final class InputController {
    var onEdge: ((Bool, Bool) -> Void)?
    var onRegistrationChange: ((HotkeyRegistrationStatus) -> Void)?
    private(set) var registrationStatus: HotkeyRegistrationStatus = .success {
        didSet { onRegistrationChange?(registrationStatus) }
    }
    #if DEBUG || TRIAL_DIAGNOSTICS
    private(set) var diagnosticSource = "none"
    private(set) var observedModifierKeyCode: UInt16?
    private var observedPressed = Set<ModifierSide>()
    private func recordSource(_ origin: InputOrigin) {
        switch origin { case .carbon: diagnosticSource = "carbon"; case .flagsPoll: diagnosticSource = "flags poll"; case .eventTap: diagnosticSource = "event tap"; case .none: diagnosticSource = "none" }
    }
    #endif
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var timer: Timer?
    private var tap: CFMachPort?
    private var runSource: CFRunLoopSource?
    private var down = false
    private var method: InputMethod = .carbon
    private var side: ModifierSide = .rightOption
    private var shortcut = Shortcut()
    private var fallback = false
    func configure(_ store: SettingsStore) {
        stop(); method = store.method; side = store.side; shortcut = store.shortcut; fallback = false
        #if DEBUG || TRIAL_DIAGNOSTICS
        observedModifierKeyCode = nil; observedPressed = []; diagnosticSource = "none"
        #endif
        if method == .carbon {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = types.withUnsafeMutableBufferPointer { InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, $0.count, $0.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handler) }
            guard status == noErr else {
                registrationStatus = HotkeyRegistrationStatus(carbonStatus: status, shortcut: shortcut)
                return
            }
            let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x43485241, id: 1), GetApplicationEventTarget(), 0, &hotkey)
            registrationStatus = HotkeyRegistrationStatus(carbonStatus: registered, shortcut: shortcut)
        } else if method == .eventTap {
            fallback = !CGPreflightListenEventAccess()
            if !fallback {
                tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue), callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let owner = Unmanaged<InputController>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.fallback = true
                        owner.registrationStatus = .modifierUnavailable(side: owner.side)
                        owner.startPollingIfNeeded()
                        #if DEBUG || TRIAL_DIAGNOSTICS
                        owner.recordSource(.none)
                        #endif
                        if owner.down { owner.onEdge?(false, true) }
                    } else if type == .flagsChanged {
                        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                        #if DEBUG || TRIAL_DIAGNOSTICS
                        if ModifierSide.from(keyCode: code) != nil { owner.observedModifierKeyCode = code }
                        #endif
                        if ModifierSide.from(keyCode: code) == owner.side {
                            owner.edge(ModifierSide.pressed(rawFlags: event.flags.rawValue).contains(owner.side), source: .eventTap)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
                if let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
                    runSource = source
                    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                    CGEvent.tapEnable(tap: tap, enable: true)
                    fallback = !CGEvent.tapIsEnabled(tap: tap)
                } else { fallback = true }
                if fallback {
                    if let runSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runSource, .commonModes) }; runSource = nil
                    if let tap { CFMachPortInvalidate(tap) }; tap = nil
                }
            }
            registrationStatus = fallback ? .modifierUnavailable(side: side) : .success
        } else {
            // Foundation's polling timer has no failable registration API.
            registrationStatus = .success
        }
        startPollingIfNeeded()
    }
    private func startPollingIfNeeded() {
        guard timer == nil, method == .flagsPoll || (method == .eventTap && fallback) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in self?.poll() }
    }
    func edge(_ next: Bool, source: InputOrigin) {
        // In toggle mode each physical press is independent; releases only reset the latch.
        guard next != down else { return }
        down = next
        #if DEBUG || TRIAL_DIAGNOSTICS
        recordSource(source)
        #endif
        onEdge?(next, fallback)
    }
    private func poll() {
        guard method == .flagsPoll || (method == .eventTap && fallback) else { return }
        let pressed = ModifierSide.pressed(rawFlags: CGEventSource.flagsState(.combinedSessionState).rawValue)
        #if DEBUG || TRIAL_DIAGNOSTICS
        // Derive the physical side from observed transitions, never from the setting.
        for observed in ModifierSide.allCases where pressed.contains(observed) != observedPressed.contains(observed) {
            observedModifierKeyCode = observed.keyCode
        }
        observedPressed = pressed
        #endif
        edge(pressed.contains(side), source: .flagsPoll)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        if let runSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runSource, .commonModes) }; runSource = nil
        if let tap { CFMachPortInvalidate(tap) }; tap = nil; down = false
    }
    deinit { stop() }
}

final class ShortcutRecorder: NSTextField {
    var recorded: ((Shortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        recorded?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        keyDown(with: event); return true
    }
    override func becomeFirstResponder() -> Bool { true }
}
