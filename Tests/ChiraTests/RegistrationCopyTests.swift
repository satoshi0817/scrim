import XCTest
@testable import ChiraCore

final class RegistrationCopyTests: XCTestCase {
    func testVerifiedDuplicateStatusUsesAlreadyRegisteredCopyWithoutNamingAnApp() {
        // Verified against installed CarbonEventsCore.h, not inferred from an earlier fixture.
        XCTAssertEqual(RegistrationFeedback.alreadyRegisteredStatus, -9878)
        XCTAssertEqual(RegistrationFeedback.internalFailureStatus, -9868)
        let status = HotkeyRegistrationStatus(carbonStatus: RegistrationFeedback.alreadyRegisteredStatus, shortcut: .default)
        XCTAssertEqual(status.message, "ショートカット ⌃⌥P を登録できませんでした。このキーはすでに登録されています。別のキーを選んでください。")
        XCTAssertFalse((status.message ?? "").contains("他のアプリ"))
        XCTAssertEqual(RegistrationFeedback.message(status), status.message)
    }

    func testOtherStatusesUseGenericActionableFailureWithoutCollisionClaim() {
        for code in [RegistrationFeedback.internalFailureStatus, -9879, -50, -1, Int32.min, Int32.max] {
            let status = HotkeyRegistrationStatus(carbonStatus: code, shortcut: .default)
            let message = status.message ?? ""
            XCTAssertTrue(message.contains("登録できませんでした"))
            XCTAssertTrue(message.contains("別のキーを選んで、もう一度お試しください"))
            for claim in ["すでに登録", "重複", "他のアプリ", "システムで使われ"] { XCTAssertFalse(message.contains(claim)) }
        }
    }

    func testAllUserFacingRegistrationPathsHideNumericCodesAndInternalIdentifiers() {
        for code in [RegistrationFeedback.alreadyRegisteredStatus, RegistrationFeedback.internalFailureStatus, -9879, -50, Int32.min, Int32.max] {
            let status = HotkeyRegistrationStatus(carbonStatus: code, shortcut: .default)
            let entry = EntryState(shortcut: .default, registration: status)
            var recording = ShortcutRecordingSession(savedShortcut: .testCopy)
            recording.begin(); recording.submit(.default); XCTAssertNil(recording.resolve(status))
            let messages = [status.message, RegistrationFeedback.message(status), entry.failureMessage, recording.feedback, entry.guideText] + entry.menuTitles.map { Optional($0) }
            for message in messages.compactMap({ $0 }) {
                XCTAssertNil(message.range(of: "[0-9]", options: .regularExpression), message)
                for identifier in ["Carbon", "OSStatus", "status:", "eventHotKey", "eventInternalErr"] {
                    XCTAssertFalse(message.contains(identifier), message)
                }
            }
        }
    }

    func testDuplicateAndGenericFailurePreserveSavedShortcutBytes() {
        for code in [RegistrationFeedback.alreadyRegisteredStatus, RegistrationFeedback.internalFailureStatus] {
            let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
            store.shortcut = .testCopy
            let original = storage.data(forKey: "shortcut")
            var recording = ShortcutRecordingSession(savedShortcut: store.shortcut)
            recording.begin(); recording.submit(.default)
            if let replacement = recording.resolve(.carbonFailure(shortcut: .default, status: code)) { store.shortcut = replacement }
            XCTAssertEqual(recording.savedShortcut, .testCopy); XCTAssertEqual(recording.phase, .recording)
            XCTAssertEqual(storage.data(forKey: "shortcut"), original)
            recording.cancel()
            XCTAssertEqual(SettingsStore(storage: storage).shortcut, .testCopy)
            XCTAssertEqual(storage.data(forKey: "shortcut"), original)
        }
    }

    func testSuccessAndRetryRecoveryRemoveFailureGuidanceBeforeCommitting() {
        let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
        store.shortcut = .testCopy
        var recording = ShortcutRecordingSession(savedShortcut: store.shortcut)
        recording.begin(); recording.submit(.default)
        XCTAssertNil(recording.resolve(.carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus)))
        recording.submit(.default)
        let success = HotkeyRegistrationStatus(carbonStatus: 0, shortcut: .default)
        XCTAssertNil(success.message); XCTAssertNil(RegistrationFeedback.message(success))
        XCTAssertNil(EntryState(shortcut: .default, registration: success).failureMessage)
        if let replacement = recording.resolve(success) { store.shortcut = replacement }
        XCTAssertEqual(SettingsStore(storage: storage).shortcut, .default)
        XCTAssertEqual(recording.feedback, "⌃⌥P を登録しました。")
        XCTAssertFalse(recording.isActive)
    }
}
