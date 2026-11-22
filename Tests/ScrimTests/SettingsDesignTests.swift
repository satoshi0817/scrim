import XCTest
@testable import ScrimCore

final class SettingsDesignTests: XCTestCase {
    func testDisplayLayoutCheckboxUsesExactDesignerTitle() {
        XCTAssertEqual(DisplayLayoutCopy.checkboxTitle, "すべてのディスプレイで同じ配置")
    }
    func testFailureKeepsNativeNeutralFieldBorderWithoutWarningOverlay() {
        for code in [RegistrationFeedback.alreadyRegisteredStatus, RegistrationFeedback.internalFailureStatus, -50] {
            for recording in [false, true] {
                let content = Trial2SettingsPresentation(retainedShortcut: .testCopy,
                    registration: .carbonFailure(shortcut: .default, status: code), isRecording: recording)
                XCTAssertEqual(content.recorderWarningBorderWidth, 0)
                XCTAssertEqual(content.recorderWarningBorderWidth,
                    Trial2SettingsPresentation(retainedShortcut: .testCopy, isRecording: recording).recorderWarningBorderWidth)
            }
        }
    }

    func testRetainedHelperImmediatelyFollowsMeasuredErrorHeight() {
        // Short, wrapped and recording-prefixed messages retain the same tight gap.
        for height in [15.0, 30, 45, 60, 80, 96] {
            XCTAssertEqual(Trial2SettingsPresentation.retainedHelperTopOffset(errorHeight: height), height + 2)
        }
        XCTAssertEqual(Trial2SettingsPresentation.errorHelperGap, 2)
    }

    func testRecordingCancelUsesCompleteLabelAndReservedButtonWidth() {
        let content = Trial2SettingsPresentation(retainedShortcut: .default, isRecording: true)
        XCTAssertEqual(content.changeButtonTitle, "キャンセル")
        XCTAssertGreaterThanOrEqual(Trial2SettingsPresentation.minimumChangeButtonWidth, 124)
        XCTAssertGreaterThanOrEqual(Trial2SettingsPresentation.minimumDefaultButtonWidth, 112)
        XCTAssertEqual(content.recorderFieldText, "⌃⌥P")
    }

    func testFailureHelperUsesRetainedConfiguredShortcut() {
        for retained in [Shortcut.testCopy, Shortcut(keyCode: 13, modifiers: 0x1800)] {
            let content = Trial2SettingsPresentation(retainedShortcut: retained,
                registration: .carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus))
            XCTAssertEqual(content.retainedHelperLine, "\(retained.displayString) のまま使えます")
            XCTAssertFalse((content.retainedHelperLine ?? "").contains(Shortcut.default.displayString))
        }
        XCTAssertNil(Trial2SettingsPresentation(retainedShortcut: .testCopy).retainedHelperLine)
    }

    func testFailureFieldShowsRetainedKeyWhileErrorShowsAttemptedKey() {
        let content = Trial2SettingsPresentation(retainedShortcut: .testCopy,
            registration: .carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus), isRecording: true)
        XCTAssertEqual(content.recorderFieldText, "⌃⌥⌘F19")
        XCTAssertTrue(content.errorLines.first?.contains("⌃⌥P") == true)
        XCTAssertFalse(content.errorLines.joined().contains(content.recorderFieldText))
        XCTAssertEqual(content.retainedHelperLine, "⌃⌥⌘F19 のまま使えます")
    }

    func testDuplicateCopyUsesSentenceLinesWithoutDanglingFragment() {
        let status = HotkeyRegistrationStatus.carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus)
        let lines = RegistrationFeedback.messageLines(status)
        XCTAssertEqual(lines, ["ショートカット ⌃⌥P を登録できませんでした。", "このキーはすでに登録されています。", "別のキーを選んでください。"])
        XCTAssertFalse(lines.contains("さい。"))
        XCTAssertEqual(lines.joined(), RegistrationFeedback.message(status))
    }

    func testFailurePresentationDoesNotChangePersistedBinding() {
        for code in [RegistrationFeedback.alreadyRegisteredStatus, RegistrationFeedback.internalFailureStatus] {
            let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
            store.shortcut = .testCopy
            let savedBytes = storage.data(forKey: "shortcut")
            let status = HotkeyRegistrationStatus.carbonFailure(shortcut: .default, status: code)
            var recording = ShortcutRecordingSession(savedShortcut: store.shortcut)
            recording.begin(); recording.submit(.default)
            if let confirmed = recording.resolve(status) { store.shortcut = confirmed }
            let presentation = Trial2SettingsPresentation(retainedShortcut: store.shortcut, registration: status, isRecording: recording.isActive)
            XCTAssertEqual(presentation.recorderFieldText, Shortcut.testCopy.displayString)
            XCTAssertEqual(presentation.retainedHelperLine, "⌃⌥⌘F19 のまま使えます")
            XCTAssertEqual(SettingsStore(storage: storage).shortcut, .testCopy)
            XCTAssertEqual(storage.data(forKey: "shortcut"), savedBytes)
        }
    }

    func testSettingsPresentationContainsNoInternalErrorCodesOrIdentifiers() {
        for code in [RegistrationFeedback.alreadyRegisteredStatus, RegistrationFeedback.internalFailureStatus, -9879, -50] {
            let content = Trial2SettingsPresentation(retainedShortcut: .testCopy, registration: .carbonFailure(shortcut: .default, status: code))
            let text = (content.errorLines + [content.recorderFieldText, content.retainedHelperLine ?? ""]).joined(separator: "\n")
            for hidden in [String(code), "Carbon", "OSStatus", "eventHotKey", "status:"] { XCTAssertFalse(text.contains(hidden), text) }
        }
    }

    func testTrial2ModifierOnlyControlsStayHiddenForAllSavedMethods() {
        let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
        for method in InputMethod.allCases {
            store.method = method
            let presentation = Trial2SettingsPresentation(retainedShortcut: store.shortcut)
            XCTAssertFalse(presentation.showsModifierOnlyControls)
            XCTAssertEqual(SettingsStore(storage: storage).method, method)
        }
    }

    func testScrimResourceVersionAndIdentity() throws {
        // Read the repository resource; this creates no preferences or plist file.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Scrim/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "10")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.satoshi0817.Scrim")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon.icns")
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            XCTAssertEqual(plist[key] as? String, "Scrim")
        }
    }
}
