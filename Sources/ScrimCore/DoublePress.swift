import Foundation
public enum CommandChoice: String, Codable, CaseIterable { case either = "どちらの ⌘ でも", left = "左だけ", right = "右だけ" }
public struct GestureSettings: Codable, Equatable {
    public var firstTapMax = 0.30, gapMax = 0.40, pinThreshold = 0.25
    public var command = CommandChoice.either
    public var useFn = false, enabled = true
    public init() {}
}
public struct GestureSnapshot {
    public var left: Bool, right: Bool, fn: Bool, otherModifiers: Bool, mouseDown: Bool
    public init(left: Bool = false, right: Bool = false, fn: Bool = false, otherModifiers: Bool = false, mouseDown: Bool = false) {
        self.left = left; self.right = right; self.fn = fn; self.otherModifiers = otherModifiers; self.mouseDown = mouseDown
    }
    public static let secondaryFnMask: UInt64 = 0x800000
    public static func hasFn(rawFlags: UInt64) -> Bool { rawFlags & secondaryFnMask != 0 }
}
public struct DoublePressMachine {
    public enum Phase: Equatable { case idle, firstDown, waiting, secondDown }
    public enum CancelReason: Equatable { case bothCommands, wrongSide, modifier, mouse, key, timeout, clock, unavailable }
    public enum Effect: Equatable { case none, peek, pin, hide, hideImmediately }
    public struct Record: Equatable { public let phase: Phase; public let cancelReason: CancelReason? }
    public private(set) var record = Record(phase: .idle, cancelReason: nil)
    public var settings: GestureSettings
    public var allowsPeekInteraction: Bool
    private var previous = false
    private var started: Int64 = 0
    private var lastTime: Int64 = -1
    private func ticks(_ seconds: Double) -> Int64 { Int64((seconds * 1_000_000_000).rounded()) }
    public init(settings: GestureSettings = GestureSettings(), allowsPeekInteraction: Bool = true) { self.settings = settings; self.allowsPeekInteraction = allowsPeekInteraction }
    @discardableResult public mutating func cancel(_ reason: CancelReason) -> Effect {
        let visible = record.phase == .secondDown
        record = Record(phase: .idle, cancelReason: reason)
        return visible ? .hideImmediately : .none
    }
    public mutating func interrupt(key: Bool) -> Effect {
        if !key && allowsPeekInteraction && record.phase == .secondDown { return .none }
        return cancel(key ? .key : .mouse)
    }
    public mutating func update(_ input: GestureSnapshot, at time: Double) -> Effect {
        guard time.isFinite, time >= 0, time < 9_000_000_000 else { return cancel(.clock) }
        let time = ticks(time)
        let pressed = settings.useFn ? input.fn : input.left || input.right
        defer { previous = pressed; lastTime = time }
        guard time >= lastTime else { return cancel(.clock) }
        guard !(input.left && input.right) else { return cancel(.bothCommands) }
        guard !input.otherModifiers, !(settings.useFn && (input.left || input.right)), !(!settings.useFn && input.fn) else { return cancel(.modifier) }
        guard !input.mouseDown || (allowsPeekInteraction && record.phase == .secondDown) else { return cancel(.mouse) }
        if !settings.useFn && ((settings.command == .left && input.right) || (settings.command == .right && input.left)) { return cancel(.wrongSide) }
        guard pressed != previous else { return .none }
        switch record.phase {
        case .idle:
            if pressed { started = time; record = Record(phase: .firstDown, cancelReason: nil) }
        case .firstDown:
            if !pressed {
                guard time <= started + ticks(settings.firstTapMax) else { return cancel(.timeout) }
                started = time; record = Record(phase: .waiting, cancelReason: nil)
            }
        case .waiting:
            if pressed {
                guard time <= started + ticks(settings.gapMax) else { return cancel(.timeout) }
                started = time; record = Record(phase: .secondDown, cancelReason: nil); return .peek
            }
        case .secondDown:
            if !pressed { record = Record(phase: .idle, cancelReason: nil); return time < started + ticks(settings.pinThreshold) ? .pin : .hide }
        }
        return .none
    }
}
public enum GesturePermissionState: String, CaseIterable { case unasked, denied, granted }
public protocol GesturePermissionChecking { func isGranted() -> Bool }
public enum GestureCopy {
    public static let action = "⌘ を2回押して、2回目を押したまま"
    public static let heading = "⌘ の2回押しを使うには、入力監視の許可が必要です"
    public static let body = "Scrim は、押したキーの内容を記録・送信しません。⌘ を押したタイミングだけを使います。"
    public static let denied = "入力監視がオフになっています", granted = "許可されました"
    public static let allow = "許可する", later = "あとで（⌃⌥P を使う）"
    public static let cautions = ["🌐キーの設定を「何もしない」にする必要があります。", "fn とほかのキーを一緒に押したときは、Scrim は開きません（Fn-D などのシステムの操作はそのまま使えます）", "Apple 以外の外付けキーボードでは動かないことがあります。", "🌐キーで入力ソースを切り替えている場合は、fn は使えません。"]
    public static func menu(permitted: Bool, secure: Bool, fn: Bool = false) -> String {
        if secure { return "パスワード入力中は ⌘ の2回押しが使えません" }
        return permitted ? (fn ? "fn を2回押して、2回目を押したまま" : action) : "⌃⌥P で使用中（⌘ の2回押しは許可待ち）"
    }
}

/// Prevents a CLI/host launch from treating inherited preflight values as app permission.
public enum GestureIdentityPolicy {
    public static func mayInspect(bundleIdentifier: String?, isAppBundle: Bool, parentPID: Int32) -> Bool {
        bundleIdentifier == "com.satoshi0817.Scrim" && isAppBundle && parentPID == 1
    }
}

public struct GesturePermissionPresentationPolicy {
    public enum Trigger { case firstRun, gestureEnabled, settingsOpened, manual }
    public private(set) var deferred: Bool
    private var firstRunHandled = false
    public init(deferred: Bool = false) { self.deferred = deferred }
    public mutating func later() { deferred = true }
    public mutating func shouldPresent(_ trigger: Trigger, granted: Bool) -> Bool {
        guard !granted else { return false }
        if trigger == .manual { return true }
        guard !deferred else { return false }
        switch trigger {
        case .firstRun:
            guard !firstRunHandled else { return false }
            firstRunHandled = true; return true
        case .gestureEnabled: return true
        case .settingsOpened, .manual: return false
        }
    }
}
public enum GestureSettingsPresentation {
    public static let waiting = "許可待ち（⌃⌥P で使用中）"
    public static let permissionButton = "入力監視を許可…"
    public static func checkboxTitle(fn: Bool) -> String { fn ? "2回押しを使う" : "⌘ の2回押しを使う" }
    public static func showsWaiting(granted: Bool) -> Bool { !granted }
    public static func commandPickerEnabled(fn: Bool) -> Bool { !fn }
    public static let collapsedHeight = 300.0, expandedHeight = 480.0
    public static let cautionHeights = [32.0, 52.0, 32.0, 32.0]
    public static let cautionTop = 222.0, cautionGap = 6.0, keyboardButtonY = 12.0
    public static let permissionCardWidth = 580.0, permissionCardHeight = 320.0
    public static let bodyWidth = 532.0, bodyHeight = 96.0
}
