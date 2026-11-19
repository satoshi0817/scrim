import AppKit
import Carbon
import ScrimCore

private let hotkeyCallback: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x43485241 else { return OSStatus(eventNotHandledErr) }
    let input = Unmanaged<InputController>.fromOpaque(context).takeUnretainedValue()
    guard id.id == input.currentIdentifier else { return OSStatus(eventNotHandledErr) }
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
    private var down = false
    private var method: InputMethod = .carbon
    private var shortcut = Shortcut.default
    private var fallback = false
    private var activeRegistrationStatus: HotkeyRegistrationStatus = .success
    private(set) var currentIdentifier: UInt32 = 1
    private var nextIdentifier: UInt32 = 1
    func configure(_ store: SettingsStore) {
        // Legacy modifier methods are no longer a shipping input path.
        stop(); method = .carbon; shortcut = store.shortcut; fallback = false
        #if DEBUG || TRIAL_DIAGNOSTICS
        observedModifierKeyCode = nil; observedPressed = []; diagnosticSource = "none"
        #endif
        if method == .carbon {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = types.withUnsafeMutableBufferPointer { InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, $0.count, $0.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handler) }
            guard status == noErr else {
                registrationStatus = HotkeyRegistrationStatus(carbonStatus: status, shortcut: shortcut)
                activeRegistrationStatus = registrationStatus
                return
            }
            nextIdentifier &+= 1; currentIdentifier = nextIdentifier
            let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x43485241, id: currentIdentifier), GetApplicationEventTarget(), 0, &hotkey)
            registrationStatus = HotkeyRegistrationStatus(carbonStatus: registered, shortcut: shortcut)
        }
        activeRegistrationStatus = registrationStatus
    }
    func restoreActiveRegistrationFeedback() { registrationStatus = activeRegistrationStatus }
    /// Try the candidate before removing the active binding. Failed attempts do not
    /// replace the active reference or write preferences.
    func registerReplacement(_ candidate: Shortcut) -> HotkeyRegistrationStatus {
        if method == .carbon, hotkey != nil, shortcut == candidate {
            activeRegistrationStatus = .success; registrationStatus = .success; return .success
        }
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let installed = types.withUnsafeMutableBufferPointer { InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, $0.count, $0.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handler) }
            guard installed == noErr else {
                registrationStatus = HotkeyRegistrationStatus(carbonStatus: installed, shortcut: candidate); return registrationStatus
            }
        }
        nextIdentifier &+= 1
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, EventHotKeyID(signature: 0x43485241, id: nextIdentifier), GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr else {
            registrationStatus = HotkeyRegistrationStatus(carbonStatus: result, shortcut: candidate); return registrationStatus
        }
        if let hotkey {
            let removed = UnregisterEventHotKey(hotkey)
            guard removed == noErr else {
                if let replacement { UnregisterEventHotKey(replacement) }
                registrationStatus = HotkeyRegistrationStatus(carbonStatus: removed, shortcut: candidate)
                return registrationStatus
            }
        }
        hotkey = replacement; currentIdentifier = nextIdentifier
        shortcut = candidate; method = .carbon; fallback = false; down = false
        activeRegistrationStatus = .success; registrationStatus = .success; return .success
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
    func stop() {
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        down = false
    }
    deinit { stop() }
}

final class ShortcutRecorder: NSTextField {
    var recording = false
    override var acceptsFirstResponder: Bool { recording }
    override func mouseDown(with event: NSEvent) { if recording { window?.makeFirstResponder(self) } }
    // Key input is consumed by the temporary, window-scoped recording monitor.
    override func keyDown(with event: NSEvent) {}
}
