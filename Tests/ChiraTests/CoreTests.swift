import XCTest
@testable import ChiraCore

final class CoreTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    override func setUp() { suite = "chira-test-"+UUID().uuidString; defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); defaults = nil; suite = nil }
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
    func testPersistenceAndURLNormalization() {
        let a = SettingsStore(defaults: defaults); a.shortcut = .testCopy; a.method = .flagsPoll; a.side = .leftControl
        let b = SettingsStore(defaults: defaults); XCTAssertEqual(b.shortcut, .testCopy); XCTAssertEqual(b.method, .flagsPoll); XCTAssertEqual(b.side, .leftControl)
        XCTAssertEqual(SettingsStore.normalize(" example.com ")?.absoluteString, "https://example.com")
        XCTAssertNil(SettingsStore.normalize("file:///tmp/private")); XCTAssertNil(SettingsStore.normalize(""))
    }
    #if DEBUG || TRIAL_DIAGNOSTICS
    func testDiagnosticsContainsOnlyAllowlistedData() {
        var d = Diagnostics(); d.deltaMS = 249; d.heldMS = 249; d.release = "https://private.invalid/user"; d.panels = 5; d.live = 4
        XCTAssertTrue(d.text.contains("249.0 ms")); XCTAssertTrue(d.text.contains("dormant: 1")); XCTAssertTrue(d.text.contains("release: none"))
        for value in ["https", "private", "/Users", "title", "url"] { XCTAssertFalse(d.text.contains(value)) }
    }
    #endif
}
