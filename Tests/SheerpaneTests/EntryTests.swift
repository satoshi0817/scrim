import XCTest
@testable import SheerpaneCore
import SheerpaneAssets

final class EntryTests: XCTestCase {
    func testRecordingOnlyAcceptsInputAfterExplicitBegin() {
        var recording = ShortcutRecordingSession(savedShortcut: .default)
        XCTAssertFalse(recording.submit(.testCopy)); XCTAssertFalse(recording.isActive)
        recording.begin(); XCTAssertEqual(recording.phase, .recording)
        XCTAssertTrue(recording.submit(.testCopy)); XCTAssertEqual(recording.phase, .registering)
        XCTAssertEqual(recording.savedShortcut, .default)
    }
    func testRecordingCancelPreservesSavedBindingAndDiscardsCandidate() {
        var recording = ShortcutRecordingSession(savedShortcut: .testCopy)
        recording.begin(); recording.submit(.default); recording.cancel()
        XCTAssertFalse(recording.isActive); XCTAssertNil(recording.candidate)
        XCTAssertEqual(recording.savedShortcut, .testCopy)
        XCTAssertNil(recording.resolve(.success))
    }
    func testRecordingValidationRejectsPlainShiftOnlyModifierAndEscapeKeys() {
        for candidate in [Shortcut(keyCode: 35, modifiers: 0), Shortcut(keyCode: 35, modifiers: 0x0200),
                          Shortcut(keyCode: 58, modifiers: 0x0800), Shortcut(keyCode: 53, modifiers: 0x1000),
                          Shortcut(keyCode: 200, modifiers: 0x1000), Shortcut(keyCode: 35, modifiers: 0x80000000)] {
            var recording = ShortcutRecordingSession(savedShortcut: .default); recording.begin()
            XCTAssertFalse(recording.submit(candidate)); XCTAssertEqual(recording.phase, .recording)
            XCTAssertNotNil(recording.feedback); XCTAssertEqual(recording.savedShortcut, .default)
        }
    }
    func testRecordingValidationAcceptsOrdinaryCombinations() {
        for flags in [UInt32(0x1000), 0x0800, 0x0100, 0x1B00] {
            XCTAssertNil(ShortcutValidation.message(for: Shortcut(keyCode: 35, modifiers: flags)))
        }
    }
    func testRecordingSuccessReturnsOnlyConfirmedReplacement() {
        var recording = ShortcutRecordingSession(savedShortcut: .default)
        recording.begin(); recording.submit(.testCopy)
        XCTAssertEqual(recording.resolve(.success), .testCopy)
        XCTAssertEqual(recording.savedShortcut, .testCopy); XCTAssertFalse(recording.isActive)
        XCTAssertNil(recording.resolve(.success))
    }
    func testRecordingFailurePreservesSavedBindingAndAllowsRetryRecovery() {
        var recording = ShortcutRecordingSession(savedShortcut: .default)
        recording.begin(); recording.submit(.testCopy)
        XCTAssertNil(recording.resolve(.carbonFailure(shortcut: .testCopy, status: -9878)))
        XCTAssertEqual(recording.savedShortcut, .default); XCTAssertEqual(recording.phase, .recording)
        XCTAssertTrue(recording.feedback?.contains("すでに登録されています") == true)
        recording.submit(.testCopy); XCTAssertEqual(recording.resolve(.success), .testCopy)
        XCTAssertFalse(recording.feedback?.contains("すでに登録されています") == true)
    }
    func testFailedAndCancelledRecordingDoNotReplacePersistedShortcut() {
        let storage = MemorySettingsStorage()
        let persisted = SettingsStore(storage: storage); persisted.shortcut = .testCopy
        let original = storage.data(forKey: "shortcut")
        var recording = ShortcutRecordingSession(savedShortcut: persisted.shortcut)
        recording.begin(); recording.submit(.default)
        if let value = recording.resolve(.carbonFailure(shortcut: .default, status: -9878)) { persisted.shortcut = value }
        recording.cancel()
        XCTAssertEqual(storage.data(forKey: "shortcut"), original)
        XCTAssertEqual(SettingsStore(storage: storage).shortcut, .testCopy)
    }
    func testConfirmedRecordingPersistsThroughFreshMemoryStore() {
        let storage = MemorySettingsStorage(), initial = Shortcut(keyCode: 49, modifiers: 0x1800)
        let store = SettingsStore(storage: storage); store.shortcut = initial
        var recording = ShortcutRecordingSession(savedShortcut: store.shortcut)
        recording.begin(); recording.submit(.default)
        if let value = recording.resolve(.success) { store.shortcut = value; store.method = .carbon }
        XCTAssertEqual(SettingsStore(storage: storage).shortcut, .default)
        XCTAssertEqual(SettingsStore(storage: storage).method, .carbon)
    }
    func testDockTrialAndReleaseDefaultsDoNotWriteStorage() {
        let storage = MemorySettingsStorage()
        let settings = SettingsStore(storage: storage)
        XCTAssertTrue(settings.dockVisible(isTrial: true)); XCTAssertFalse(settings.dockVisible(isTrial: false))
        XCTAssertNil(storage.data(forKey: "dockVisible"))
    }
    func testDockExplicitSavedChoiceWinsAcrossBuildDefaults() {
        let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
        for choice in [false, true] {
            store.dockVisible = choice
            let fresh = SettingsStore(storage: storage)
            XCTAssertEqual(fresh.dockVisible(isTrial: true), choice)
            XCTAssertEqual(fresh.dockVisible(isTrial: false), choice)
        }
    }
    func testDockReadingCompiledDefaultDoesNotWriteStorage() {
        let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
        XCTAssertEqual(store.dockVisible, SheerpaneBuild.isTrial)
        XCTAssertNil(storage.data(forKey: "dockVisible"))
    }
    func testEntryMenuAndGuideFollowCurrentShortcut() {
        let entry = EntryState(shortcut: .testCopy)
        XCTAssertEqual(entry.menuTitles, ["開く (⌃⌥⌘F19)", "設定…", "Sheerpane を終了"])
        XCTAssertEqual(entry.guideText, "Sheerpane は画面上部のメニューバーにいます。\n⌃⌥⌘F19 を押している間だけ表示します。")
    }
    func testEntryWarningStateAndRecoverySelectDesignerTemplates() {
        let error = EntryState(shortcut: .default, registration: .carbonFailure(shortcut: .default, status: -9878))
        XCTAssertTrue(error.showsWarning); XCTAssertNotNil(error.failureMessage)
        let recovered = EntryState(shortcut: .default)
        XCTAssertFalse(recovered.showsWarning); XCTAssertNil(recovered.failureMessage)
        XCTAssertEqual(StatusIcon.resourceName(warning: error.showsWarning), "MenuBarWarningTemplate")
        XCTAssertEqual(StatusIcon.resourceName(warning: recovered.showsWarning), "MenuBarTemplate")
    }
    func testEntryGenericFailureIsActionableWithoutInventingConflict() {
        let message = RegistrationFeedback.message(.carbonFailure(shortcut: .default, status: -50)) ?? ""
        XCTAssertTrue(message.contains("⌃⌥P")); XCTAssertTrue(message.contains("もう一度お試しください"))
        XCTAssertFalse(message.contains("登録されています")); XCTAssertFalse(message.contains("-50"))
    }
    func testMenuOpenPinsOverlayWithoutChangingHoldTapBehavior() {
        var machine = HoldTapStateMachine(); machine.pin()
        XCTAssertEqual(machine.state, .pinned); XCTAssertFalse(machine.state.ignoresMouse)
        machine.dismiss(); machine.press(at: 0); machine.release(at: 0.25)
        XCTAssertEqual(machine.state, .hidden)
    }
}
