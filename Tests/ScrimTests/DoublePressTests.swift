import XCTest
import CoreGraphics
@testable import ScrimCore
final class DoublePressTests: XCTestCase {
    let down = GestureSnapshot(left: true), up = GestureSnapshot()
    func second(_ machine: inout DoublePressMachine, first: Double = 0.1, second: Double = 0.2) -> DoublePressMachine.Effect {
        _ = machine.update(down, at: 0); _ = machine.update(up, at: first)
        return machine.update(down, at: second)
    }
    func testFirstTapInclusive030() { var m = DoublePressMachine(); XCTAssertEqual(second(&m, first: 0.30, second: 0.7), .peek) }
    func testFirstTapOver030() { var m = DoublePressMachine(); XCTAssertEqual(second(&m, first: 0.300001, second: 0.4), .none) }
    func testGapInclusive040() { var m = DoublePressMachine(); XCTAssertEqual(second(&m, first: 0.1, second: 0.5), .peek) }
    func testGapOver040() { var m = DoublePressMachine(); XCTAssertEqual(second(&m, first: 0.1, second: 0.500001), .none) }
    func testPinStrictlyBelow025() { var m = DoublePressMachine(); XCTAssertEqual(second(&m), .peek); XCTAssertEqual(m.update(up, at: 0.449999), .pin) }
    func testHideAt025() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.update(up, at: 0.45), .hide) }
    func testHideAbove025() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.update(up, at: 1), .hide) }
    func testEitherSideLeftThenRight() { var m = DoublePressMachine(); _ = m.update(down, at: 0); _ = m.update(up, at: 0.1); XCTAssertEqual(m.update(GestureSnapshot(right: true), at: 0.2), .peek) }
    func testEitherSideRightThenLeft() { var m = DoublePressMachine(); _ = m.update(GestureSnapshot(right: true), at: 0); _ = m.update(up, at: 0.1); XCTAssertEqual(m.update(down, at: 0.2), .peek) }
    func testLeftOnlyRejectsRight() { var s = GestureSettings(); s.command = .left; var m = DoublePressMachine(settings: s); _ = m.update(GestureSnapshot(right: true), at: 0); XCTAssertEqual(m.record.cancelReason, .wrongSide) }
    func testRightOnlyRejectsLeft() { var s = GestureSettings(); s.command = .right; var m = DoublePressMachine(settings: s); _ = m.update(down, at: 0); XCTAssertEqual(m.record.cancelReason, .wrongSide) }
    func testBothCommandsCancel() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.update(GestureSnapshot(left: true, right: true), at: 0.3), .hideImmediately) }
    func testCommandCSecondHoldHidesNeverPins() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.interrupt(key: true), .hideImmediately); XCTAssertEqual(m.update(up, at: 0.21), .none); XCTAssertEqual(m.record.phase, .idle) }
    func testCommandTabCancelsFirstTap() { var m = DoublePressMachine(); _ = m.update(down, at: 0); _ = m.interrupt(key: true); _ = m.update(up, at: 0.1); XCTAssertEqual(m.update(down, at: 0.2), .none) }
    func testCommandClickDuringInteractivePeekStaysVisible() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.interrupt(key: false), .none); XCTAssertEqual(m.update(up, at: 1), .hide) }
    func testClickThroughPeekCanStillBeSelected() { var m = DoublePressMachine(allowsPeekInteraction: false); _ = second(&m); XCTAssertEqual(m.interrupt(key: false), .hideImmediately) }
    func testMouseAlreadyDownCannotStart() { var m = DoublePressMachine(); _ = m.update(GestureSnapshot(left: true, mouseDown: true), at: 0); XCTAssertEqual(m.record.phase, .idle) }
    func testOtherModifierAlreadyDownCannotStart() { var m = DoublePressMachine(); _ = m.update(GestureSnapshot(left: true, otherModifiers: true), at: 0); XCTAssertEqual(m.record.phase, .idle) }
    func testModifierChangeDuringPeek() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.update(GestureSnapshot(left: true, otherModifiers: true), at: 0.21), .hideImmediately) }
    func testFnSecondaryMask() { XCTAssertEqual(GestureSnapshot.secondaryFnMask, CGEventFlags.maskSecondaryFn.rawValue); XCTAssertTrue(GestureSnapshot.hasFn(rawFlags: 0x800000)); XCTAssertFalse(GestureSnapshot.hasFn(rawFlags: 0x100000)) }
    func testFnDoublePress() { var s = GestureSettings(); s.useFn = true; var m = DoublePressMachine(settings: s); _ = m.update(GestureSnapshot(fn: true), at: 0); _ = m.update(up, at: 0.1); XCTAssertEqual(m.update(GestureSnapshot(fn: true), at: 0.2), .peek); XCTAssertEqual(m.interrupt(key: true), .hideImmediately) }
    func testAdjustableThresholdsInMemory() { let store = SettingsStore(storage: MemorySettingsStorage()); store.gesture.firstTapMax = 0.5; store.gesture.gapMax = 0.6; store.gesture.pinThreshold = 0.1; var m = DoublePressMachine(settings: store.gesture); XCTAssertEqual(second(&m, first: 0.5, second: 1.1), .peek); XCTAssertEqual(m.update(up, at: 1.2), .hide) }
    func testPermissionAndMenuCopy() { XCTAssertEqual(GestureCopy.heading, "⌘ の2回押しを使うには、入力監視の許可が必要です"); XCTAssertEqual(GestureCopy.body, "Scrim は、押したキーの内容を記録・送信しません。⌘ を押したタイミングだけを使います。"); XCTAssertEqual(GestureCopy.allow, "許可する"); XCTAssertEqual(GestureCopy.later, "あとで（⌃⌥P を使う）"); XCTAssertEqual(GestureCopy.denied, "入力監視がオフになっています"); XCTAssertEqual(GestureCopy.granted, "許可されました"); XCTAssertEqual(GestureCopy.menu(permitted: true, secure: false), GestureCopy.action); XCTAssertEqual(GestureCopy.menu(permitted: false, secure: false), "⌃⌥P で使用中（⌘ の2回押しは許可待ち）"); XCTAssertEqual(GestureCopy.menu(permitted: true, secure: true), "パスワード入力中は ⌘ の2回押しが使えません"); XCTAssertEqual(GestureCopy.cautions.count, 4) }
    func testInjectedPermissionPort() { struct Denied: GesturePermissionChecking { func isGranted() -> Bool { false } }; XCTAssertFalse(Denied().isGranted()) }
    func testHostIdentityCannotUseInheritedPreflight() {
        XCTAssertFalse(GestureIdentityPolicy.mayInspect(bundleIdentifier: "com.satoshi0817.Scrim", isAppBundle: true, parentPID: 42))
        XCTAssertFalse(GestureIdentityPolicy.mayInspect(bundleIdentifier: "host.helper", isAppBundle: true, parentPID: 1))
        XCTAssertFalse(GestureIdentityPolicy.mayInspect(bundleIdentifier: "com.satoshi0817.Scrim", isAppBundle: false, parentPID: 1))
        XCTAssertTrue(GestureIdentityPolicy.mayInspect(bundleIdentifier: "com.satoshi0817.Scrim", isAppBundle: true, parentPID: 1))
    }
    func testBothCommandsCancelInEveryMode() {
        for choice in CommandChoice.allCases { var s = GestureSettings(); s.command = choice; var m = DoublePressMachine(settings: s); _ = m.update(GestureSnapshot(left: true, right: true), at: 0); XCTAssertEqual(m.record.cancelReason, .bothCommands) }
    }
    func testRestrictedSideMismatchOnSecondPress() {
        for choice in [CommandChoice.left, .right] {
            var s = GestureSettings(); s.command = choice; var m = DoublePressMachine(settings: s)
            _ = m.update(GestureSnapshot(left: choice == .left, right: choice == .right), at: 0)
            _ = m.update(up, at: 0.1)
            XCTAssertEqual(m.update(GestureSnapshot(left: choice == .right, right: choice == .left), at: 0.2), .none)
            XCTAssertEqual(m.record.cancelReason, .wrongSide)
        }
    }
    func testClockReversalHidesPeek() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.update(up, at: 0.1), .hideImmediately) }
    func testUnavailableHidesPeekWithoutPin() { var m = DoublePressMachine(); _ = second(&m); XCTAssertEqual(m.cancel(.unavailable), .hideImmediately); XCTAssertEqual(m.update(up, at: 0.21), .none) }

    func testResearcherConfirmedFnCautionCopy() {
        XCTAssertEqual(GestureCopy.cautions, [
            "🌐キーの設定を「何もしない」にする必要があります。",
            "fn とほかのキーを一緒に押したときは、Scrim は開きません（Fn-D などのシステムの操作はそのまま使えます）",
            "Apple 以外の外付けキーボードでは動かないことがあります。",
            "🌐キーで入力ソースを切り替えている場合は、fn は使えません。"
        ])
    }
    func testFnOtherKeyDuringFirstHoldDoesNotOpen() {
        var settings = GestureSettings(); settings.useFn = true
        var m = DoublePressMachine(settings: settings)
        _ = m.update(GestureSnapshot(fn: true), at: 0)
        XCTAssertEqual(m.interrupt(key: true), .none) // Fn-D: no key value enters the machine.
        XCTAssertEqual(m.record.cancelReason, .key)
        XCTAssertEqual(m.update(up, at: 0.1), .none)
        XCTAssertEqual(m.update(GestureSnapshot(fn: true), at: 0.2), .none)
        XCTAssertEqual(m.record.phase, .firstDown)
    }
    func testFnOtherKeyBetweenPressesDoesNotOpen() {
        var settings = GestureSettings(); settings.useFn = true
        var m = DoublePressMachine(settings: settings)
        _ = m.update(GestureSnapshot(fn: true), at: 0); _ = m.update(up, at: 0.1)
        _ = m.interrupt(key: true)
        XCTAssertEqual(m.update(GestureSnapshot(fn: true), at: 0.2), .none)
    }
    func testPermissionFirstRunAutoPresentsOnlyOnce() {
        var p = GesturePermissionPresentationPolicy()
        XCTAssertTrue(p.shouldPresent(.firstRun, granted: false))
        XCTAssertFalse(p.shouldPresent(.firstRun, granted: false))
    }
    func testUnauthorizedSettingsOpenNeverAutoPresents() {
        var p = GesturePermissionPresentationPolicy()
        XCTAssertFalse(p.shouldPresent(.settingsOpened, granted: false))
        XCTAssertFalse(p.shouldPresent(.settingsOpened, granted: false))
        XCTAssertTrue(p.shouldPresent(.gestureEnabled, granted: false))
    }
    func testGestureEnableAndCommandReselectAutoPresent() {
        var p = GesturePermissionPresentationPolicy()
        XCTAssertTrue(p.shouldPresent(.gestureEnabled, granted: false))
        XCTAssertTrue(p.shouldPresent(.gestureEnabled, granted: false)) // fn off -> Command reselected
    }
    func testLaterSuppressesAllFutureAutoPresentButAllowsManualCard() {
        var p = GesturePermissionPresentationPolicy(); p.later()
        for trigger in [GesturePermissionPresentationPolicy.Trigger.firstRun, .gestureEnabled, .settingsOpened] {
            XCTAssertFalse(p.shouldPresent(trigger, granted: false))
        }
        XCTAssertTrue(p.shouldPresent(.manual, granted: false))
    }
    func testLaterPersistsUsingMemoryStorageOnly() {
        let storage = MemorySettingsStorage(); let store = SettingsStore(storage: storage)
        store.gesturePermissionDeferred = true
        var p = GesturePermissionPresentationPolicy(deferred: SettingsStore(storage: storage).gesturePermissionDeferred)
        XCTAssertFalse(p.shouldPresent(.firstRun, granted: false))
        XCTAssertFalse(p.shouldPresent(.gestureEnabled, granted: false))
    }
    func testGrantedNeverPresentsPermissionCard() {
        var p = GesturePermissionPresentationPolicy()
        for trigger in [GesturePermissionPresentationPolicy.Trigger.firstRun, .gestureEnabled, .settingsOpened, .manual] {
            XCTAssertFalse(p.shouldPresent(trigger, granted: true))
        }
    }
    func testWaitingRowAndFnControlsPresentation() {
        XCTAssertEqual(GestureSettingsPresentation.waiting, "許可待ち（⌃⌥P で使用中）")
        XCTAssertEqual(GestureSettingsPresentation.permissionButton, "入力監視を許可…")
        XCTAssertTrue(GestureSettingsPresentation.showsWaiting(granted: false))
        XCTAssertFalse(GestureSettingsPresentation.showsWaiting(granted: true))
        XCTAssertEqual(GestureSettingsPresentation.checkboxTitle(fn: true), "2回押しを使う")
        XCTAssertEqual(GestureSettingsPresentation.checkboxTitle(fn: false), "⌘ の2回押しを使う")
        XCTAssertFalse(GestureSettingsPresentation.commandPickerEnabled(fn: true))
        XCTAssertTrue(GestureSettingsPresentation.commandPickerEnabled(fn: false))
    }
    func testExpandedCautionsLeaveButtonBelowTextAndCardBodyHasRoom() {
        let p = GestureSettingsPresentation.self
        let bottom = p.cautionTop - p.cautionHeights.reduce(0, +) - p.cautionGap * 3
        XCTAssertGreaterThan(bottom, p.keyboardButtonY + 28)
        XCTAssertGreaterThanOrEqual(p.cautionHeights[1], 48) // long Fn-D explanation wraps
        XCTAssertGreaterThanOrEqual(p.bodyHeight, 90)
        XCTAssertLessThan(124 + p.bodyHeight, 230) // body below heading
        XCTAssertGreaterThan(p.expandedHeight, p.collapsedHeight)
    }

}
