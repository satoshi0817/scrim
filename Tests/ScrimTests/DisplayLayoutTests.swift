import XCTest
import CoreGraphics
@testable import ScrimCore

final class DisplayLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 1600, height: 1000)
    private func layout(count: Int = 3) -> DisplayLayout {
        DisplayLayout(panels: (0..<count).map {
            PanelRecord(url: URL(string: "https://example.invalid/\($0)")!, placement:
                FractionalFrame(frame: CGRect(x: 20 + $0 * 520, y: 300, width: 480, height: 320), screen: canvas))
        }, referenceSize: canvas)
    }
    private func assertInside(_ frames: [CGRect], _ size: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.minX, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, size.height + 0.001, file: file, line: line)
        }
    }
    func testSharedLayoutPreservesScreenFractionsAndPanelOrderIndependence() {
        let fixture = layout()
        let target = CGSize(width: 1200, height: 750)
        let frames = LayoutFitter.relativeFrames(layout: fixture, screen: target)
        assertInside(frames, target)
        for (record, frame) in zip(fixture.panels, frames) {
            XCTAssertEqual(frame.minX / target.width, record.placement.x, accuracy: 0.00001)
            XCTAssertEqual(frame.minY / target.height, record.placement.y, accuracy: 0.00001)
            XCTAssertEqual(frame.width / target.width, record.placement.width, accuracy: 0.00001)
            XCTAssertEqual(frame.height / target.height, record.placement.height, accuracy: 0.00001)
        }
        var reversed = fixture; reversed.panels.reverse()
        XCTAssertEqual(LayoutFitter.relativeFrames(layout: reversed, screen: target), Array(frames.reversed()))
    }
    func testComfortableScreenPreservesCanonicalGeometry() {
        let fixture = layout()
        XCTAssertEqual(LayoutFitter.frames(layout: fixture, screen: canvas), LayoutFitter.canonicalFrames(layout: fixture))
        XCTAssertFalse(LayoutFitter.needsFitting(layout: fixture, screen: canvas))
    }
    func testSmallerFramesStayInsideScreenForContentReflow() {
        let target = CGSize(width: 1200, height: 750)
        let frames = LayoutFitter.frames(layout: layout(), screen: target)
        assertInside(frames, target)
        XCTAssertTrue(LayoutFitter.needsFitting(layout: layout(), screen: target))
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.width, LayoutFitter.minimumPanelSize.width)
            XCTAssertGreaterThanOrEqual(frame.height, LayoutFitter.minimumPanelSize.height)
            XCTAssertLessThan(frame.width, 480)
        }
    }
    func testMinimumScaleWrapsDownwardInRecordOrder() {
        let target = CGSize(width: 650, height: 600)
        let frames = LayoutFitter.frames(layout: layout(), screen: target)
        assertInside(frames, target)
        XCTAssertEqual(LayoutFitter.minimumScale, 0.6)
        XCTAssertGreaterThanOrEqual(frames[0].width, LayoutFitter.minimumPanelSize.width)
        XCTAssertGreaterThan(frames[1].minX, frames[0].minX)
        XCTAssertEqual(frames[1].minY, frames[0].minY)
        XCTAssertEqual(frames[2].minX, 0)
        XCTAssertLessThan(frames[2].maxY, frames[0].minY)
        XCTAssertFalse(frames[0].intersects(frames[2]))
    }
    func testCascadeExposesTitleBarStripsInsteadOfCompressingRows() {
        var fixture = layout(count: 12)
        fixture.panels = fixture.panels.enumerated().map { index, record in
            var copy = record
            copy.placement = FractionalFrame(frame: CGRect(x: index * 260, y: 0, width: 240, height: 160), screen: canvas)
            return copy
        }
        let target = CGSize(width: 500, height: 400)
        let frames = LayoutFitter.frames(layout: fixture, screen: target)
        assertInside(frames, target)
        XCTAssertEqual(frames.count, 12)
        XCTAssertEqual(LayoutFitter.titleBarHeight, 28)
        for i in 1..<frames.count {
            XCTAssertEqual(frames[i-1].maxY-frames[i].maxY, LayoutFitter.titleBarHeight, accuracy: 0.001)
            let titleBottom = frames[i-1].maxY-LayoutFitter.titleBarHeight
            XCTAssertGreaterThanOrEqual(titleBottom, 0)
            XCTAssertLessThanOrEqual(frames[i].maxY, titleBottom+0.001)
        }
        XCTAssertGreaterThanOrEqual(frames.last!.height, LayoutFitter.titleBarHeight)
    }
    func testPhysicallyTinyScreenStillContainsFrames() {
        let target = CGSize(width: 200, height: 100)
        let frames = LayoutFitter.frames(layout: layout(), screen: target)
        assertInside(frames, target)
    }
    func testMoreTitlesThanScreenHeightExposesMaximumEqualStrips() {
        let screen = CGSize(width: 200, height: 100)
        let frames = LayoutFitter.frames(layout: layout(count: 12), screen: screen)
        assertInside(frames, screen)
        for i in 1..<frames.count {
            XCTAssertEqual(frames[i-1].maxY-frames[i].maxY, screen.height/12, accuracy: 0.001)
        }
    }
    func testFittedSaveAndReorderPreserveSharedCanonicalGeometry() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let canonical = layout()
        store.saveLayout(canonical, for: "uuid:large")
        let target = CGSize(width: 650, height: 600)
        let frames = LayoutFitter.frames(layout: canonical, screen: target)
        let wasFitted = LayoutFitter.needsFitting(layout: canonical, screen: target)
        XCTAssertTrue(wasFitted)
        var presented = canonical.panels
        for i in presented.indices { presented[i].placement = FractionalFrame(frame: frames[i], screen: target) }
        store.savePresentedLayout(DisplayLayout(panels: presented, referenceSize: target), for: "uuid:small", wasFitted: wasFitted)
        XCTAssertEqual(store.panels.map(\.placement), canonical.panels.map(\.placement))
        XCTAssertEqual(store.sharedLayoutReferenceSize, canvas)
        presented = [presented[2], presented[0], presented[1]]
        store.savePresentedLayout(DisplayLayout(panels: presented, referenceSize: target), for: "uuid:small", wasFitted: wasFitted)
        XCTAssertEqual(store.panels.map(\.id), [canonical.panels[2].id, canonical.panels[0].id, canonical.panels[1].id])
        let original = Dictionary(uniqueKeysWithValues: canonical.panels.map { ($0.id, $0.placement) })
        for panel in store.panels { XCTAssertEqual(panel.placement, original[panel.id]) }
        XCTAssertEqual(store.sharedLayoutReferenceSize, canvas)
    }
    func testFittedAddRemoveRetainsRemainingSharedPlacements() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let canonical = layout()
        store.saveLayout(canonical, for: "uuid:a")
        let added = layout(count: 1).panels[0]
        let shown = DisplayLayout(panels: [canonical.panels[1], added], referenceSize: CGSize(width: 650, height: 600))
        store.savePresentedLayout(shown, for: "uuid:a", wasFitted: true)
        XCTAssertEqual(store.panels.map(\.id), shown.panels.map(\.id))
        XCTAssertEqual(store.panels[0].placement, canonical.panels[1].placement)
        XCTAssertEqual(store.sharedLayoutReferenceSize, canvas)
    }
    func testUnfittedSharedEditsAndDisplaySpecificFittedEditsSaveGeometry() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let original = layout(count: 1)
        store.saveLayout(original, for: "uuid:a")
        var edited = original
        edited.panels[0].placement = FractionalFrame(frame: CGRect(x: 64, y: 80, width: 560, height: 400), screen: canvas)
        XCTAssertFalse(LayoutFitter.needsFitting(layout: edited, screen: canvas))
        store.savePresentedLayout(edited, for: "uuid:a", wasFitted: false)
        XCTAssertEqual(store.panels.map(\.placement), edited.panels.map(\.placement))
        store.sameLayoutOnAllDisplays = false
        var perDisplay = edited; perDisplay.referenceSize = CGSize(width: 800, height: 600)
        store.savePresentedLayout(perDisplay, for: "uuid:b", wasFitted: true)
        XCTAssertEqual(store.layoutsByDisplay["uuid:b"]?.referenceSize, perDisplay.referenceSize)
        XCTAssertEqual(store.sharedLayoutReferenceSize, canvas)
    }
    func testPerDisplayArrangementsShareContentAndSurviveReload() {
        let storage = MemorySettingsStorage()
        let store = SettingsStore(storage: storage)
        store.panels = layout().panels
        let shared = store.layout(for: "uuid:a", screen: canvas)
        store.setSameLayoutOnAllDisplays(false)
        // A display without its own arrangement looks exactly like the shared layout did on that screen.
        let small = CGSize(width: 1200, height: 750)
        let first = store.layout(for: "uuid:a", screen: small)
        XCTAssertEqual(first.panels.map(\.placement), shared.panels.map(\.placement))
        XCTAssertEqual(first.referenceSize, small)
        XCTAssertEqual(LayoutFitter.frames(layout: first, screen: small), LayoutFitter.relativeFrames(layout: shared, screen: small))
        var moved = store.layout(for: "uuid:a", screen: canvas)
        moved.panels[0].placement = FractionalFrame(frame: CGRect(x: 40, y: 40, width: 400, height: 300), screen: canvas)
        store.saveLayout(moved, for: "uuid:a")
        XCTAssertEqual(store.layout(for: "uuid:a", screen: canvas).panels[0].placement, moved.panels[0].placement)
        XCTAssertEqual(store.layout(for: "uuid:b", screen: canvas).panels[0].placement, shared.panels[0].placement)
        XCTAssertEqual(store.panels[0].placement, shared.panels[0].placement)
        var edited = store.layout(for: "uuid:a", screen: canvas)
        edited.panels.removeLast()
        edited.panels[1].url = URL(string: "https://example.invalid/changed")!
        store.saveLayout(edited, for: "uuid:a")
        let other = store.layout(for: "uuid:b", screen: canvas)
        XCTAssertEqual(other.panels.map(\.id), edited.panels.map(\.id))
        XCTAssertEqual(other.panels[1].url, edited.panels[1].url)
        XCTAssertEqual(store.panels.count, 2)
        let durable = SettingsStore(storage: storage)
        XCTAssertFalse(durable.sameLayoutOnAllDisplays)
        XCTAssertEqual(durable.sharedLayoutReferenceSize, canvas)
        XCTAssertEqual(durable.panels.map(\.id), edited.panels.map(\.id))
        XCTAssertEqual(durable.layoutsByDisplay["uuid:a"]?.panels.map(\.id), edited.panels.map(\.id))
        XCTAssertEqual(durable.layoutsByDisplay["uuid:a"]?.referenceSize, canvas)
        XCTAssertNil(durable.layoutsByDisplay["uuid:b"])
    }
    func testPanelAddedOnOneDisplayJoinsOtherArrangementsAtItsFractions() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let base = layout(count: 2)
        store.panels = base.panels
        store.setSameLayoutOnAllDisplays(false)
        var b = store.layout(for: "uuid:b", screen: canvas)
        b.panels.reverse()
        store.saveLayout(b, for: "uuid:b")
        var a = store.layout(for: "uuid:a", screen: canvas)
        let added = layout(count: 1).panels[0]
        a.panels.append(added)
        store.saveLayout(a, for: "uuid:a")
        let shownOnB = store.layout(for: "uuid:b", screen: canvas)
        XCTAssertEqual(shownOnB.panels.map(\.id), [base.panels[1].id, base.panels[0].id, added.id])
        XCTAssertEqual(shownOnB.panels.last?.placement, added.placement)
        XCTAssertEqual(store.panels.map(\.id), base.panels.map(\.id) + [added.id])
    }
    func testSwitchingBackAdoptsMostRecentlyEditedDisplay() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.panels = layout().panels; store.sharedLayoutReferenceSize = canvas
        store.setSameLayoutOnAllDisplays(false)
        var a = store.layout(for: "uuid:a", screen: canvas)
        a.panels[0].placement = FractionalFrame(frame: CGRect(x: 40, y: 40, width: 400, height: 300), screen: canvas)
        store.saveLayout(a, for: "uuid:a")
        let small = CGSize(width: 1200, height: 750)
        var b = store.layout(for: "uuid:b", screen: small)
        b.panels.reverse()
        b.panels[0].placement = FractionalFrame(frame: CGRect(x: 100, y: 100, width: 300, height: 200), screen: small)
        store.saveLayout(b, for: "uuid:b")
        var layouts = store.layoutsByDisplay
        XCTAssertNotNil(layouts["uuid:a"]?.editedAt)
        XCTAssertNotNil(layouts["uuid:b"]?.editedAt)
        layouts["uuid:a"]?.editedAt = Date(timeIntervalSince1970: 100)
        layouts["uuid:b"]?.editedAt = Date(timeIntervalSince1970: 200)
        store.layoutsByDisplay = layouts
        store.setSameLayoutOnAllDisplays(true)
        XCTAssertTrue(store.sameLayoutOnAllDisplays)
        XCTAssertEqual(store.panels.map(\.id), b.panels.map(\.id))
        XCTAssertEqual(store.panels.map(\.placement), b.panels.map(\.placement))
        XCTAssertEqual(store.sharedLayoutReferenceSize, small)
        XCTAssertTrue(store.layoutsByDisplay.isEmpty)
        store.setSameLayoutOnAllDisplays(false)
        XCTAssertEqual(store.layout(for: "uuid:a", screen: canvas).panels.map(\.placement), b.panels.map(\.placement))
    }
    func testContentOnlySaveKeepsSharedGeometryWhenSwitchingBack() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.panels = layout().panels; store.sharedLayoutReferenceSize = canvas
        let before = store.panels.map(\.placement)
        store.setSameLayoutOnAllDisplays(false)
        var a = store.layout(for: "uuid:a", screen: CGSize(width: 1200, height: 750))
        let changed = URL(string: "https://example.invalid/changed")!
        a.panels[0].url = changed
        store.saveLayout(a, for: "uuid:a")
        XCTAssertNil(store.layoutsByDisplay["uuid:a"]?.editedAt)
        var b = store.layout(for: "uuid:b", screen: canvas)
        b.panels.append(b.panels.removeFirst())
        store.saveLayout(b, for: "uuid:b")
        XCTAssertEqual(store.layout(for: "uuid:b", screen: canvas).panels.map(\.id), b.panels.map(\.id))
        XCTAssertNil(store.layoutsByDisplay["uuid:b"]?.editedAt, "Bringing a panel forward is not a rearrangement")
        store.setSameLayoutOnAllDisplays(true)
        XCTAssertEqual(store.panels.map(\.placement), before)
        XCTAssertEqual(store.sharedLayoutReferenceSize, canvas)
        XCTAssertEqual(store.panels[0].url, changed)
    }
    func testLegacyPerDisplayContentIsSharedOnce() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        let base = layout(count: 2)
        store.panels = base.panels; store.sameLayoutOnAllDisplays = false
        let extra = layout(count: 1).panels[0]
        store.layoutsByDisplay = ["uuid:b": DisplayLayout(panels: [base.panels[1], extra], referenceSize: canvas)]
        store.shareLegacyDisplayContent()
        XCTAssertEqual(store.panels.map(\.id), base.panels.map(\.id) + [extra.id])
        XCTAssertEqual(store.layout(for: "uuid:b", screen: canvas).panels.map(\.id), [base.panels[1].id, extra.id, base.panels[0].id])
        var shown = store.layout(for: "uuid:a", screen: canvas)
        shown.panels.removeAll { $0.id == extra.id }
        store.saveLayout(shown, for: "uuid:a")
        store.shareLegacyDisplayContent()
        XCTAssertFalse(store.panels.contains { $0.id == extra.id })
        XCTAssertEqual(store.layoutsByDisplay["uuid:b"]?.panels.contains { $0.id == extra.id }, false)
    }
    func testDisplaysCanTurnOverlayOffIndividually() {
        let storage = MemorySettingsStorage()
        let store = SettingsStore(storage: storage)
        XCTAssertTrue(store.showsOverlay(on: "uuid:a"))
        store.setShowsOverlay(false, on: "uuid:a")
        store.setShowsOverlay(false, on: "ephemeral:x")
        XCTAssertFalse(store.showsOverlay(on: "uuid:a"))
        XCTAssertTrue(store.showsOverlay(on: "uuid:b"))
        XCTAssertTrue(store.showsOverlay(on: "ephemeral:x"))
        XCTAssertFalse(SettingsStore(storage: storage).showsOverlay(on: "uuid:a"))
        store.setShowsOverlay(true, on: "uuid:a")
        XCTAssertTrue(store.showsOverlay(on: "uuid:a"))
    }
    func testReferenceSizesPersistAsWidthHeightObjects() throws {
        let storage = MemorySettingsStorage()
        let store = SettingsStore(storage: storage)
        let reference = CGSize(width: 1440.5, height: 900.25)
        store.saveLayout(DisplayLayout(panels: layout().panels, referenceSize: reference), for: "uuid:a")
        store.sameLayoutOnAllDisplays = false
        let displayReference = CGSize(width: 1920, height: 1080)
        store.saveLayout(DisplayLayout(panels: layout(count: 1).panels, referenceSize: displayReference), for: "uuid:b")
        let fresh = SettingsStore(storage: storage)
        XCTAssertEqual(fresh.sharedLayoutReferenceSize, reference)
        XCTAssertEqual(fresh.layoutsByDisplay["uuid:b"]?.referenceSize, displayReference)
        XCTAssertEqual(fresh.layoutsByDisplay["uuid:b"]?.panels.count, 1)
        let sharedBytes = try XCTUnwrap(storage.data(forKey: "sharedLayoutReferenceSize"))
        let sharedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: sharedBytes) as? [String: Double])
        XCTAssertEqual(sharedJSON, ["width": 1440.5, "height": 900.25])
        let displayBytes = try XCTUnwrap(storage.data(forKey: "layoutsByDisplay"))
        let displayJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: displayBytes) as? [String: [String: Any]])
        let sizeJSON = try XCTUnwrap(displayJSON["uuid:b"]?["referenceSize"] as? [String: Double])
        XCTAssertEqual(sizeJSON, ["width": 1920, "height": 1080])
    }
    func testUnseenDisplayIsNotSavedUntilEdited() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.panels = layout().panels; store.sameLayoutOnAllDisplays = false
        let shown = store.layout(for: "uuid:new", screen: canvas)
        XCTAssertEqual(shown.panels.map(\.id), store.panels.map(\.id))
        XCTAssertTrue(store.layoutsByDisplay.isEmpty)
    }
    private struct FakeUUIDs: DisplayUUIDProviding {
        var mapping: [CGDirectDisplayID: String]
        func uuid(for displayID: CGDirectDisplayID) -> String? { mapping[displayID] }
    }
    func testReconnectWithChangedNumericIDRestoresOnlySameUUID() {
        let identity = DisplayIdentity(provider: FakeUUIDs(mapping: [1: "A", 99: "A", 2: "B"]))
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.panels = layout().panels; store.sameLayoutOnAllDisplays = false
        var arranged = store.layout(for: identity.key(for: 1), screen: canvas)
        arranged.panels[0].placement = FractionalFrame(frame: CGRect(x: 40, y: 40, width: 400, height: 300), screen: canvas)
        store.saveLayout(arranged, for: identity.key(for: 1))
        identity.forgetUnavailable(connected: [])
        XCTAssertEqual(identity.key(for: 1), identity.key(for: 99))
        XCTAssertEqual(store.layout(for: identity.key(for: 99), screen: canvas).panels[0].placement, arranged.panels[0].placement)
        XCTAssertEqual(store.layout(for: identity.key(for: 2), screen: canvas).panels[0].placement, store.panels[0].placement)
        XCTAssertNotEqual(store.panels[0].placement, arranged.panels[0].placement)
    }
    func testMissingUUIDNeverReusesPersistedLayoutOrAnotherDisplayKey() {
        let identity = DisplayIdentity(provider: FakeUUIDs(mapping: [:]))
        let first = identity.key(for: 1)
        XCTAssertEqual(first, identity.key(for: 1))
        XCTAssertNotEqual(first, identity.key(for: 2))
        identity.forgetUnavailable(connected: [2])
        XCTAssertNotEqual(first, identity.key(for: 1))
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.sameLayoutOnAllDisplays = false
        store.saveLayout(layout(), for: first)
        XCTAssertTrue(store.layoutsByDisplay.isEmpty)
        XCTAssertEqual(store.panels.count, 3)
    }
    func testPre008MigrationPreservesFractionsAndReadOnlyChiraSource() throws {
        final class Domain: SettingsMigrationStorage {
            var values: [String: Any]; var writes = 0
            init(_ values: [String: Any]) { self.values = values }
            func snapshot() -> [String: Any] { values }
            func set(_ value: Any, forKey key: String) { writes += 1; values[key] = value }
        }
        let records = layout().panels, bytes = try JSONEncoder().encode(layout().panels)
        let source = Domain(["panels": bytes]), destination = Domain([:])
        let before = NSDictionary(dictionary: source.values)
        SettingsMigration.migrate(source: source, destination: destination)
        let storage = MemorySettingsStorage()
        storage.setData(destination.values["panels"] as? Data, forKey: "panels")
        let store = SettingsStore(storage: storage)
        XCTAssertEqual(store.panels.map(\.placement), records.map(\.placement))
        XCTAssertTrue(store.sameLayoutOnAllDisplays)
        XCTAssertTrue(store.layoutsByDisplay.isEmpty)
        XCTAssertNil(store.sharedLayoutReferenceSize)
        _ = store.layout(for: "uuid:a", screen: canvas)
        XCTAssertEqual(store.sharedLayoutReferenceSize, canvas)
        XCTAssertEqual(storage.data(forKey: "panels"), bytes)
        XCTAssertEqual(NSDictionary(dictionary: source.values), before)
        XCTAssertEqual(source.writes, 0)
    }
}
