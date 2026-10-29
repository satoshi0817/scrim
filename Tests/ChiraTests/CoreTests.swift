import XCTest
@testable import ChiraCore

final class CoreTests: XCTestCase {
    func testPermissionGuidanceUsesExactDesignerWording() {
        XCTAssertEqual(GuideContent.permissionNoteText, "修飾キーだけで使う場合は、入力監視の許可が必要です。")
        XCTAssertEqual(GuideContent.permissionRequestTitle, "入力監視の許可をリクエスト")
    }
    func testUserFacingGuidePermissionTextDoesNotMentionMethodB() {
        for method in InputMethod.allCases {
            let content = GuideContent(method: method)
            for text in [content.permissionNote, content.permissionBlockText, GuideContent.permissionRequestTitle, GuideContent.permissionGrantedText] {
                XCTAssertFalse((text ?? "").contains("方式 B"))
            }
        }
    }
    func testCarbonDefaultGuideHidesPermissionBlock() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        XCTAssertEqual(store.method, .carbon)
        let content = GuideContent(method: store.method)
        XCTAssertFalse(content.showsPermissionNote); XCTAssertNil(content.permissionNote); XCTAssertNil(content.permissionBlockText)
    }
    func testFlagsPollingGuideShowsPermissionBlock() {
        let content = GuideContent(method: .flagsPoll)
        XCTAssertTrue(content.showsPermissionNote); XCTAssertEqual(content.permissionNote, GuideContent.permissionNoteText)
        XCTAssertEqual(content.permissionBlockText, GuideContent.permissionNoteText)
    }
    func testEventTapGuideShowsPermissionBlock() {
        let content = GuideContent(method: .eventTap)
        XCTAssertTrue(content.showsPermissionNote); XCTAssertEqual(content.permissionNote, GuideContent.permissionNoteText)
        XCTAssertEqual(content.permissionBlockText, GuideContent.permissionNoteText + "\n" + GuideContent.fallbackNoteText)
    }
    func testTapBoundaryAndVisibility() {
        for (duration, expected) in [(0.249, OverlayState.pinned), (0.25, .hidden), (0.251, .hidden)] {
            var m = HoldTapStateMachine(); m.press(at: 0)
            XCTAssertEqual(m.state, .peek); XCTAssertTrue(m.state.ignoresMouse); XCTAssertFalse(m.state.needsKey)
            m.release(at: duration); XCTAssertEqual(m.state, expected)
        }
    }
    func testPinnedCloseAndDismissal() {
        for close in 0..<3 {
            var m = HoldTapStateMachine(); m.press(at: 0); m.release(at: 0.1)
            XCTAssertFalse(m.state.ignoresMouse); XCTAssertTrue(m.state.needsKey)
            if close == 0 { m.press(at: 1); m.release(at: 1.1) } else { m.dismiss() } // Esc and backdrop use dismiss.
            XCTAssertEqual(m.state, .hidden)
        }
    }
    func testToggleAndMissingReleaseFallback() {
        var m = HoldTapStateMachine(); m.press(at: 0, toggle: true); XCTAssertEqual(m.state, .pinned)
        m.press(at: 1, toggle: true); XCTAssertEqual(m.state, .hidden)
        m.press(at: 2); m.fallback(); XCTAssertEqual(m.state, .pinned)
        m.press(at: 3, toggle: true); XCTAssertEqual(m.state, .hidden)
    }
    func testPoolRetentionRevivalAndCap() {
        var pool = PanelPool(); let ids = (0..<13).map { _ in UUID() }
        for id in ids.prefix(4) { XCTAssertTrue(pool.add(id)) }
        let generation = pool.entries[0].webViewGeneration
        var m = HoldTapStateMachine(); m.press(at: 0); m.release(at: 1); m.press(at: 2)
        XCTAssertEqual(pool.entries[0].webViewGeneration, generation)
        pool.add(ids[4]); XCTAssertFalse(pool.entries[0].live)
        pool.view(ids[0]); XCTAssertTrue(pool.entries[0].live); XCTAssertEqual(pool.entries[0].webViewGeneration, generation+1); XCTAssertFalse(pool.entries[1].live)
        for id in ids.dropFirst(5).prefix(7) { XCTAssertTrue(pool.add(id)) }
        XCTAssertFalse(pool.add(ids[12])); XCTAssertEqual(pool.entries.count, 12); XCTAssertEqual(pool.entries.filter(\.live).count, 4)
        pool.remove(ids[0]); XCTAssertTrue(pool.add(ids[12]))
    }
    func testFractionsAcrossDisplays() {
        let f = FractionalFrame(frame: CGRect(x: 160, y: 80, width: 400, height: 240), screen: CGSize(width: 1600, height: 800))
        XCTAssertEqual(f.restore(screen: CGSize(width: 1600, height: 800)), CGRect(x: 160, y: 80, width: 400, height: 240))
        XCTAssertEqual(f.restore(screen: CGSize(width: 3200, height: 1600)), CGRect(x: 320, y: 160, width: 800, height: 480))
    }
    func testPlacementRules() {
        let screen = CGSize(width: 1800, height: 1169)
        let r = Placement.constrain(CGRect(x: 19, y: 21, width: 20, height: 30), screen: screen)
        XCTAssertEqual(r, CGRect(x: 16, y: 24, width: 240, height: 160))
        let snap = Placement.constrain(CGRect(x: 505, y: 100, width: 240, height: 160), screen: screen, others: [CGRect(x: 100, y: 400, width: 400, height: 300)])
        XCTAssertEqual(snap.minX, 500)
        let left = Placement.constrain(CGRect(x: -5000, y: -5000, width: 400, height: 240), screen: screen)
        XCTAssertEqual(left.maxX, 40); XCTAssertEqual(left.maxY, 40)
        let right = Placement.constrain(CGRect(x: 5000, y: 5000, width: 400, height: 240), screen: screen)
        XCTAssertEqual(right.minX, 1760); XCTAssertEqual(right.minY, 1129)
    }
    func testModifierSides() {
        for side in ModifierSide.allCases {
            XCTAssertEqual(ModifierSide.from(keyCode: side.keyCode), side)
            XCTAssertEqual(ModifierSide.pressed(rawFlags: side.mask), [side])
        }
        XCTAssertNil(ModifierSide.from(keyCode: 45))
        XCTAssertEqual(ModifierSide.pressed(rawFlags: 0x20000000), [])
    }
    func testMemoryShortcutPersistenceAndURLNormalization() {
        let storage = MemorySettingsStorage()
        let a = SettingsStore(storage: storage); a.shortcut = .testCopy; a.method = .flagsPoll; a.side = .leftControl
        let b = SettingsStore(storage: storage); XCTAssertEqual(b.shortcut, .testCopy); XCTAssertEqual(b.method, .flagsPoll); XCTAssertEqual(b.side, .leftControl)
        XCTAssertEqual(SettingsStore.normalize(" example.com ")?.absoluteString, "https://example.com")
        XCTAssertNil(SettingsStore.normalize("file:///tmp/private")); XCTAssertNil(SettingsStore.normalize(""))
    }
    func testDefaultShortcutIsControlOptionSpace() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        XCTAssertEqual(Shortcut().keyCode, 49)
        XCTAssertEqual(store.shortcut, Shortcut(keyCode: 49, modifiers: 0x1000 | 0x0800))
        XCTAssertEqual(store.shortcut.displayString, "⌃⌥Space")
    }
    func testRegistrationSuccessHasNoMessage() {
        let status = HotkeyRegistrationStatus(carbonStatus: 0, shortcut: Shortcut())
        XCTAssertEqual(status, .success); XCTAssertNil(status.message)
    }
    func testRegistrationFailureIncludesShortcutDisplayString() throws {
        let shortcut = Shortcut()
        let status = HotkeyRegistrationStatus(carbonStatus: -9878, shortcut: shortcut)
        let message = try XCTUnwrap(status.message)
        XCTAssertTrue(message.contains(shortcut.displayString))
        XCTAssertTrue(message.contains("登録できませんでした"))
        XCTAssertTrue(message.hasSuffix("上の欄で別のキーを押してください。"))
        XCTAssertFalse(message.contains("-9878")); XCTAssertFalse(message.contains("コード"))
        XCTAssertEqual(message, "ショートカット ⌃⌥Space を登録できませんでした（他のアプリと重複している可能性があります）。上の欄で別のキーを押してください。")
        for privateField in ["https://", "/Users/", "title", "url"] { XCTAssertFalse(message.contains(privateField)) }
    }
    func testRegistrationRecoveryClearsMessage() {
        var status = HotkeyRegistrationStatus(carbonStatus: -9878, shortcut: Shortcut())
        XCTAssertNotNil(status.message)
        status = HotkeyRegistrationStatus(carbonStatus: 0, shortcut: .testCopy)
        XCTAssertEqual(status, .success); XCTAssertNil(status.message)
    }
    func testModifierMonitorFailureHasActionableMessage() throws {
        let message = try XCTUnwrap(HotkeyRegistrationStatus.modifierUnavailable(side: .rightOption).message)
        XCTAssertTrue(message.contains("右 Option")); XCTAssertTrue(message.contains("ポーリング"))
        XCTAssertTrue(message.hasSuffix("上の欄で別のキーを押してください。"))
    }
    func testTestCopyShortcutOverrideRemainsControlOptionCommandF19() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.shortcut = .testCopy
        XCTAssertEqual(store.shortcut.keyCode, 80); XCTAssertEqual(store.shortcut.modifiers, 0x1000 | 0x0800 | 0x0100)
        XCTAssertEqual(store.shortcut.displayString, "⌃⌥⌘F19")
    }
    func testTwentyVisibilityCyclesRetainWebViewGenerationsWithoutOrderOut() {
        var pool = PanelPool()
        for _ in 0..<4 { pool.add(UUID()) }
        let generations = pool.entries.map(\.webViewGeneration)
        var machine = HoldTapStateMachine()
        for cycle in 0..<20 {
            let time = Double(cycle)*2
            machine.press(at: time)
            let peek = VisibilityPlan(state: machine.state)
            XCTAssertEqual(peek.alpha, 1); XCTAssertFalse(peek.usesOrderOut)
            machine.release(at: time+0.125)
            let pinned = VisibilityPlan(state: machine.state)
            XCTAssertTrue(pinned.makeKey); XCTAssertFalse(pinned.usesOrderOut)
            machine.dismiss()
            let hidden = VisibilityPlan(state: machine.state)
            XCTAssertEqual(hidden.alpha, 0); XCTAssertTrue(hidden.ignoresMouseEvents)
            XCTAssertEqual(hidden.fadeDuration, 0.15); XCTAssertFalse(hidden.usesOrderOut)
            XCTAssertEqual(pool.entries.map(\.webViewGeneration), generations)
        }
    }
    func testPeekVisibilityPlanIgnoresMouseAndNeverMakesKey() {
        let plan = VisibilityPlan(state: .peek)
        XCTAssertTrue(plan.ignoresMouseEvents); XCTAssertFalse(plan.makeKey)
        XCTAssertFalse(plan.showPinnedPill); XCTAssertFalse(plan.usesOrderOut); XCTAssertEqual(plan.fadeDuration, 0)
    }
    func testPeekVisibilityPlanHidesPanelMenuButton() {
        XCTAssertFalse(VisibilityPlan(state: .peek).showsPanelMenuButton)
    }
    func testPinnedVisibilityPlanShowsPanelMenuButton() {
        XCTAssertTrue(VisibilityPlan(state: .pinned).showsPanelMenuButton)
    }
    func testHiddenVisibilityPlanHidesPanelMenuButton() {
        XCTAssertFalse(VisibilityPlan(state: .hidden).showsPanelMenuButton)
    }
    func testPinnedVisibilityPlanMakesKeyOnEveryReshow() {
        for _ in 0..<20 {
            let pinned = VisibilityPlan(state: .pinned)
            XCTAssertTrue(pinned.makeKey); XCTAssertTrue(pinned.showPinnedPill)
            XCTAssertFalse(pinned.ignoresMouseEvents); XCTAssertFalse(pinned.usesOrderOut)
            let hidden = VisibilityPlan(state: .hidden)
            XCTAssertFalse(hidden.makeKey); XCTAssertFalse(hidden.showPinnedPill); XCTAssertFalse(hidden.usesOrderOut)
        }
    }
    func testSnapYEdgeToAnotherPanel() {
        let r = Placement.constrain(CGRect(x: 800, y: 705, width: 240, height: 160), screen: CGSize(width: 1800, height: 1169), others: [CGRect(x: 100, y: 400, width: 400, height: 300)])
        XCTAssertEqual(r.minY, 700)
    }
    func testResizeConstrainNeverBelowMinimumSize() {
        for size in [CGFloat(-100), 0, 1, 159, 239] {
            let r = Placement.constrain(CGRect(x: 100, y: 100, width: size, height: size), screen: CGSize(width: 1800, height: 1169))
            XCTAssertGreaterThanOrEqual(r.width, 240); XCTAssertGreaterThanOrEqual(r.height, 160)
        }
    }
    func testOddFrameValuesSnapToEightPointGrid() {
        let r = Placement.constrain(CGRect(x: 101, y: 115, width: 333, height: 275), screen: CGSize(width: 1800, height: 1169))
        XCTAssertEqual(r, CGRect(x: 104, y: 112, width: 336, height: 272))
    }
    func testFortyPointClampOnLeftSide() {
        let r = clamped(x: -5000, y: 200); XCTAssertEqual(r.maxX, 40)
    }
    func testFortyPointClampOnRightSide() {
        let r = clamped(x: 5000, y: 200); XCTAssertEqual(r.minX, 1760)
    }
    func testFortyPointClampOnBottomSide() {
        let r = clamped(x: 200, y: -5000); XCTAssertEqual(r.maxY, 40)
    }
    func testFortyPointClampOnTopSide() {
        let r = clamped(x: 200, y: 5000); XCTAssertEqual(r.minY, 1129)
    }
    private func clamped(x: CGFloat, y: CGFloat) -> CGRect {
        Placement.constrain(CGRect(x: x, y: y, width: 400, height: 240), screen: CGSize(width: 1800, height: 1169))
    }
    func testFractionalFrameJSONRoundTripThroughMemorySettingsPanels() throws {
        let storage = MemorySettingsStorage()
        let original = PanelRecord(url: URL(string: "https://example.invalid")!, placement: FractionalFrame(frame: CGRect(x: 160, y: 80, width: 400, height: 240), screen: CGSize(width: 1600, height: 800)))
        SettingsStore(storage: storage).panels = [original]
        let data = try XCTUnwrap(storage.data(forKey: "panels"))
        let decoded = try JSONDecoder().decode([PanelRecord].self, from: data)
        let restored = try XCTUnwrap(SettingsStore(storage: storage).panels.first)
        XCTAssertEqual(decoded.first?.placement, original.placement)
        XCTAssertEqual(restored.id, original.id); XCTAssertEqual(restored.url, original.url); XCTAssertEqual(restored.placement, original.placement)
        XCTAssertEqual(restored.placement.restore(screen: CGSize(width: 3200, height: 1600)), CGRect(x: 320, y: 160, width: 800, height: 480))
    }
    func testMemoryStorageShortcutAndPanelsPersistenceAcrossFreshStores() throws {
        let storage = MemorySettingsStorage()
        let a = SettingsStore(storage: storage)
        a.shortcut = .testCopy; a.method = .eventTap; a.side = .rightShift; a.guided = true
        a.panels = [PanelRecord(url: URL(string: "https://example.invalid")!, placement: FractionalFrame(frame: CGRect(x: 80, y: 160, width: 400, height: 240), screen: CGSize(width: 1600, height: 800)))]
        let b = SettingsStore(storage: storage)
        XCTAssertEqual(b.shortcut, .testCopy); XCTAssertEqual(b.method, .eventTap); XCTAssertEqual(b.side, .rightShift); XCTAssertTrue(b.guided)
        XCTAssertEqual(b.panels.first?.placement, a.panels.first?.placement); XCTAssertEqual(b.panels.first?.id, a.panels.first?.id)
    }
    func testReviveDormantPanelEvictsExactlyOneOtherAndKeepsFourLive() {
        var pool = PanelPool(); let ids = (0..<5).map { _ in UUID() }
        for id in ids { pool.add(id) }
        XCTAssertFalse(pool.entries[0].live)
        let previouslyLive = Set(pool.entries.filter(\.live).map(\.id))
        pool.view(ids[0])
        let nowLive = Set(pool.entries.filter(\.live).map(\.id))
        XCTAssertEqual(nowLive.count, 4); XCTAssertEqual(previouslyLive.subtracting(nowLive).count, 1)
        XCTAssertEqual(nowLive.subtracting(previouslyLive), [ids[0]])
        XCTAssertFalse(pool.entries[1].live)
    }
    func testAddingPanelAtTwelveIsRejectedWithoutChangingPool() {
        var pool = PanelPool()
        for _ in 0..<12 { XCTAssertTrue(pool.add(UUID())) }
        let ids = pool.entries.map(\.id), generations = pool.entries.map(\.webViewGeneration)
        XCTAssertFalse(pool.add(UUID())); XCTAssertEqual(pool.entries.map(\.id), ids)
        XCTAssertEqual(pool.entries.map(\.webViewGeneration), generations); XCTAssertEqual(pool.entries.filter(\.live).count, 4)
    }
    func testDeviceFlagsDetectBothLeftAndRightModifiersTogether() {
        for (left, right) in [(ModifierSide.leftCommand, ModifierSide.rightCommand), (.leftOption, .rightOption), (.leftControl, .rightControl), (.leftShift, .rightShift)] {
            XCTAssertEqual(ModifierSide.pressed(rawFlags: 0x20000000 | left.mask | right.mask), [left, right])
        }
    }
    func testTapExactlyQuarterSecondIsHold() {
        var m = HoldTapStateMachine(); m.press(at: 0); m.release(at: 0.25); XCTAssertEqual(m.state, .hidden)
    }
    func testSecondTapWhilePinnedCloses() {
        var m = HoldTapStateMachine(); m.press(at: 0); m.release(at: 0.1); XCTAssertEqual(m.state, .pinned)
        m.press(at: 1); m.release(at: 1.1); XCTAssertEqual(m.state, .hidden)
    }
    func testEscapeDismissesPinnedOverlay() {
        var m = HoldTapStateMachine(); m.press(at: 0); m.release(at: 0.1); m.dismiss(); XCTAssertEqual(m.state, .hidden)
    }
    func testBackdropDismissesPinnedOverlay() {
        var m = HoldTapStateMachine(); m.press(at: 0); m.release(at: 0.1); m.dismiss(); XCTAssertEqual(m.state, .hidden)
    }
    func testModifierToggleModeOpensAndClosesOnPressOnly() {
        var m = HoldTapStateMachine(); m.press(at: 0, toggle: true); XCTAssertEqual(m.state, .pinned)
        m.release(at: 10); XCTAssertEqual(m.state, .pinned)
        m.press(at: 11, toggle: true); XCTAssertEqual(m.state, .hidden)
        m.release(at: 12); XCTAssertEqual(m.state, .hidden)
    }
    #if DEBUG || TRIAL_DIAGNOSTICS
    func testDiagnosticsFormatsObservedPhysicalModifierSide() {
        var d = Diagnostics(); XCTAssertTrue(d.text.contains("modifier keyCode: none"))
        d.keyCode = 61; XCTAssertTrue(d.text.contains("61 (rightOption)"))
        d.keyCode = 58; XCTAssertTrue(d.text.contains("58 (leftOption)"))
    }
    func testDiagnosticsContainsOnlyAllowlistedData() {
        var d = Diagnostics(); d.deltaMS = 249; d.heldMS = 249; d.release = "https://private.invalid/user"; d.panels = 5; d.live = 4
        XCTAssertTrue(d.text.contains("249.0 ms")); XCTAssertTrue(d.text.contains("dormant: 1")); XCTAssertTrue(d.text.contains("release: none"))
        for value in ["https", "private", "/Users", "title", "url"] { XCTAssertFalse(d.text.contains(value)) }
    }
    #endif
}
