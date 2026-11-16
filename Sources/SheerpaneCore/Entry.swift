import Foundation

public enum SheerpaneBuild {
    public static var isTrial: Bool {
        #if DEBUG || TRIAL_DIAGNOSTICS
        return true
        #else
        return false
        #endif
    }
}

public struct EntryState: Equatable {
    public static let locationSentence = "Sheerpane は画面上部のメニューバーにいます。"
    public let shortcut: Shortcut
    public let registration: HotkeyRegistrationStatus
    public init(shortcut: Shortcut, registration: HotkeyRegistrationStatus = .success) {
        self.shortcut = shortcut; self.registration = registration
    }
    public var openTitle: String { "開く (\(shortcut.displayString))" }
    public var menuTitles: [String] { [openTitle, "設定…", "Sheerpane を終了"] }
    public var showsWarning: Bool { registration != .success }
    public var guideText: String { Self.locationSentence + "\n" + GuideContent.shortcutSentence(shortcut: shortcut) }
    public var failureMessage: String? { RegistrationFeedback.message(registration) }
}

/// Describes only the result supplied by Carbon/the monitor, not inferred conflicts.
public enum RegistrationFeedback {
    // Verified in the installed macOS 14.5/15.5 SDK CarbonEventsCore.h.
    // The duplicate status also covers registration within the current process;
    // it does not identify another application or guarantee exclusive registration.
    public static let alreadyRegisteredStatus: Int32 = -9878 // eventHotKeyExistsErr
    public static let internalFailureStatus: Int32 = -9868 // eventInternalErr
    public static func message(_ status: HotkeyRegistrationStatus) -> String? {
        let lines = messageLines(status)
        return lines.isEmpty ? nil : lines.joined()
    }
    /// Sentence boundaries are preserved for narrow settings layouts, without
    /// changing the plain-text wording used in status menus.
    public static func messageLines(_ status: HotkeyRegistrationStatus) -> [String] {
        switch status {
        case .success: return []
        case .carbonFailure(let shortcut, let code):
            let prefix = "ショートカット \(shortcut.displayString) を登録できませんでした。"
            if code == alreadyRegisteredStatus {
                return [prefix, "このキーはすでに登録されています。", "別のキーを選んでください。"]
            }
            return [prefix, "別のキーを選んで、もう一度お試しください。"]
        case .modifierUnavailable:
            return ["修飾キーのイベント監視を利用できません。", "ポーリングで開閉します。", "設定でキーの組み合わせを選べます。"]
        }
    }
}

/// Trial.2 presentation keeps the saved binding separate from an attempted key.
public struct Trial2SettingsPresentation: Equatable {
    public static let cancelTitle = "キャンセル"
    public static let minimumChangeButtonWidth: Double = 124
    public static let minimumDefaultButtonWidth: Double = 112
    public let retainedShortcut: Shortcut
    public let registration: HotkeyRegistrationStatus
    public let isRecording: Bool
    public init(retainedShortcut: Shortcut, registration: HotkeyRegistrationStatus = .success, isRecording: Bool = false) {
        self.retainedShortcut = retainedShortcut; self.registration = registration; self.isRecording = isRecording
    }
    /// Preserve the native neutral bezel; communicate registration failures in text only.
    public var recorderWarningBorderWidth: Double { 0 }
    public static let errorHelperGap: Double = 2
    /// Offset from the error's top to the helper's top, using measured text height.
    public static func retainedHelperTopOffset(errorHeight: Double) -> Double {
        errorHeight + errorHelperGap
    }
    public var recorderFieldText: String { retainedShortcut.displayString }
    public var changeButtonTitle: String { isRecording ? Self.cancelTitle : "変更" }
    public var errorLines: [String] { RegistrationFeedback.messageLines(registration) }
    public var retainedHelperLine: String? {
        registration == .success ? nil : "\(retainedShortcut.displayString) のまま使えます"
    }
    public var showsModifierOnlyControls: Bool { false }
}

public enum ShortcutValidation {
    public static func message(for shortcut: Shortcut) -> String? {
        if shortcut.modifiers & ~UInt32(0x1B00) != 0 { return "対応していない修飾キーです。" }
        if shortcut.modifiers & UInt32(0x1900) == 0 { return "Control・Option・Command のいずれかと通常のキーを押してください。" }
        if shortcut.keyCode > 126 || [53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(shortcut.keyCode) {
            return "通常のキーを組み合わせてください。Esc はキャンセルです。"
        }
        return nil
    }
}

/// Stores only keycode/modifier configuration. No event text enters this model.
public struct ShortcutRecordingSession: Equatable {
    public enum Phase: Equatable { case idle, recording, registering }
    public private(set) var phase: Phase = .idle
    public private(set) var savedShortcut: Shortcut
    public private(set) var candidate: Shortcut?
    public private(set) var feedback: String?
    public var isActive: Bool { phase != .idle }
    public init(savedShortcut: Shortcut) { self.savedShortcut = savedShortcut }
    public mutating func begin() { phase = .recording; candidate = nil; feedback = nil }
    public mutating func cancel() { phase = .idle; candidate = nil; feedback = "変更をキャンセルしました。保存済みのキーは維持されています。" }
    @discardableResult public mutating func submit(_ shortcut: Shortcut) -> Bool {
        guard phase == .recording else { return false }
        if let invalid = ShortcutValidation.message(for: shortcut) { feedback = invalid; return false }
        candidate = shortcut; phase = .registering; feedback = "登録を確認中…"; return true
    }
    /// Returns a value to persist only after successful registration.
    public mutating func resolve(_ status: HotkeyRegistrationStatus) -> Shortcut? {
        guard phase == .registering, let candidate else { return nil }
        self.candidate = nil
        guard status == .success else { phase = .recording; feedback = RegistrationFeedback.message(status); return nil }
        savedShortcut = candidate; phase = .idle; feedback = "\(candidate.displayString) を登録しました。"; return candidate
    }
}
