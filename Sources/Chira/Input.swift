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
    #if DEBUG || TRIAL_DIAGNOSTICS
    private(set) var diagnosticSource = "none"
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
    private var pressedAt = 0.0
    private var fallback = false
    func configure(_ store: SettingsStore) {
        stop(); method = store.method; side = store.side; shortcut = store.shortcut; fallback = false
        if method == .carbon {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = types.withUnsafeMutableBufferPointer { InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, $0.count, $0.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handler) }
            if status == noErr { RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x43485241, id: 1), GetApplicationEventTarget(), 0, &hotkey) }
        } else if method == .eventTap {
            fallback = !CGPreflightListenEventAccess()
            if !fallback {
                tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue), callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let owner = Unmanaged<InputController>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.fallback = true
                        #if DEBUG || TRIAL_DIAGNOSTICS
                        owner.recordSource(.none)
                        #endif
                        if owner.down { owner.onEdge?(false, true) }
                    } else if ModifierSide.from(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode))) == owner.side {
                        owner.edge(ModifierSide.pressed(rawFlags: event.flags.rawValue).contains(owner.side), source: .eventTap)
                    }
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
                if let tap { runSource = CFMachPortCreateRunLoopSource(nil, tap, 0); if let runSource { CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes) }; CGEvent.tapEnable(tap: tap, enable: true) }
                else { fallback = true }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in self?.poll() }
    }
    func edge(_ next: Bool, source: InputOrigin) {
        // In toggle mode each physical press is independent; releases only reset the latch.
        guard next != down else { return }
        down = next
        if next { pressedAt = ProcessInfo.processInfo.systemUptime }
        #if DEBUG || TRIAL_DIAGNOSTICS
        recordSource(source)
        #endif
        onEdge?(next, fallback)
    }
    private func poll() {
        if method == .flagsPoll || (method == .eventTap && fallback) {
            edge(ModifierSide.pressed(rawFlags: CGEventSource.flagsState(.combinedSessionState).rawValue).contains(side), source: .flagsPoll)
        } else if method == .carbon && down {
            // Detect missing Carbon release without an arbitrary maximum hold duration.
            if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode)), ProcessInfo.processInfo.systemUptime-pressedAt > 0.1 {
                fallback = true; down = false
                #if DEBUG || TRIAL_DIAGNOSTICS
                recordSource(.none)
                #endif
                onEdge?(false, true)
            }
        }
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
