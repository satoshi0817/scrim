import XCTest
import AppKit
@testable import SheerpaneCore
import SheerpaneAssets

final class FilePanelTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sheerpane-TASK-007-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }
    private func fixture(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("<html><title>Fixture</title><p>Local test</p></html>".utf8).write(to: url)
        return url
    }
    private func record(_ url: URL) -> PanelRecord {
        PanelRecord(url: url, placement: FractionalFrame(frame: CGRect(x: 20, y: 30, width: 480, height: 336), screen: CGSize(width: 1000, height: 800)))
    }
    func testClosingFilePanelPreservesOriginalFile() throws {
        let url = try fixture("close-panel.html")
        let original = try Data(contentsOf: url)
        let panel = record(url)
        XCTAssertEqual(PanelSource.classify(panel.url), .html(url))
        var records = [panel]
        var pool = PanelPool()
        XCTAssertTrue(pool.add(panel.id))
        let store = SettingsStore(storage: MemorySettingsStorage())
        store.panels = records

        // The same metadata action used by the real file/web panel menu.
        PanelActions.close(panel.id, records: &records, pool: &pool)
        store.panels = records

        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(pool.entries.isEmpty)
        XCTAssertTrue(store.panels.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testLocalDocumentClassification() throws {
        let pdf = try fixture("test.PDF")
        XCTAssertEqual(PanelSource.classify(pdf), .pdf(pdf))
        for ext in ["html", "htm", "xhtml"] {
            let url = try fixture("test." + ext)
            XCTAssertEqual(PanelSource.classify(url), .html(url))
        }
        for scheme in ["http", "https"] {
            let url = URL(string: scheme + "://example.invalid")!
            XCTAssertEqual(PanelSource.classify(url), .web(url))
        }
        for name in ["test.txt", "test.png", "no-extension"] {
            XCTAssertEqual(PanelSource.classify(try fixture(name)), .unreadable)
        }
        XCTAssertEqual(PanelSource.classify(directory), .unreadable)
        XCTAssertNil(SettingsStore.normalize(directory.absoluteString))
    }
    func testExtensionlessFilesRequirePDFSignature() throws {
        let pdf = directory.appendingPathComponent("extensionless-pdf")
        try Data("%PDF-1.4\nSynthetic classification fixture".utf8).write(to: pdf)
        XCTAssertEqual(PanelSource.classify(pdf), .pdf(pdf))

        let html = try fixture("extensionless-html")
        XCTAssertEqual(PanelSource.classify(html), .unreadable)
    }
    func testUnsupportedAndMissingFileReasons() throws {
        for name in ["unsupported.txt", "unsupported.png", "extensionless-html"] {
            let state = FilePanelState(url: try fixture(name))
            XCTAssertEqual(state.failureReason, .unsupported)
            XCTAssertEqual(state.reason, "PDF と HTML のファイルを開けます。")
        }
        let url = try fixture("vanishing.html")
        let storage = MemorySettingsStorage()
        SettingsStore(storage: storage).panels = [record(url)]
        try FileManager.default.removeItem(at: url)
        let restored = try XCTUnwrap(SettingsStore(storage: storage).panels.first)
        let missing = FilePanelState(url: restored.url)
        XCTAssertEqual(missing.failureReason, .missing)
        XCTAssertEqual(missing.message, "このファイルは表示できません")
        XCTAssertEqual(missing.reason, "ファイルが移動または削除された可能性があります。")
        let content = FilePanelErrorView(frame: CGRect(x: 0, y: 0, width: 466, height: 293))
        content.apply(missing)
        XCTAssertEqual(content.reasonLabel.stringValue, missing.reason)
        XCTAssertFalse(content.reasonLabel.isHidden)
        XCTAssertEqual(content.reasonLabel.textColor, NSColor.secondaryLabelColor)
    }
    func testLoadFailureOmitsReasonLine() throws {
        var state = FilePanelState(url: try fixture("load.html"))
        state.loadFailed()
        XCTAssertEqual(state.message, "このファイルは表示できません")
        XCTAssertEqual(state.failureReason, .loadFailure)
        XCTAssertNil(state.reason)
        let content = FilePanelErrorView(frame: .zero)
        content.apply(state)
        XCTAssertTrue(content.reasonLabel.isHidden)
    }
    func testUnreadableMissingAndFailedLoadsUseSameMessage() throws {
        for url in [try fixture("unsupported.txt"), directory.appendingPathComponent("missing.pdf"), directory!] {
            let panel = record(url)
            XCTAssertEqual(FilePanelState(url: panel.url).message, "このファイルは表示できません")
        }
        var state = FilePanelState(url: try fixture("declared.html"))
        XCTAssertNil(state.message)
        state.loadFailed()
        XCTAssertEqual(state.message, "このファイルは表示できません")
        // Invalid PDF is classified as PDF; PDFDocument failure uses the same transition.
        state = FilePanelState(url: try fixture("invalid.pdf"))
        state.loadFailed()
        XCTAssertEqual(state.message, "このファイルは表示できません")
    }
    func testFileRestoreAndDeletedFileRestoreFromMemory() throws {
        let storage = MemorySettingsStorage()
        let first = SettingsStore(storage: storage)
        let url = try fixture("saved.html")
        first.panels = [record(url), record(url)]
        let restored = SettingsStore(storage: storage).panels
        XCTAssertEqual(restored.count, 2)
        XCTAssertNotEqual(restored[0].id, restored[1].id)
        XCTAssertEqual(restored[0].url, url)
        XCTAssertEqual(FilePanelState(url: restored[0].url).source, .html(url))
        try FileManager.default.removeItem(at: url)
        let missing = SettingsStore(storage: storage).panels
        XCTAssertEqual(missing[0].id, restored[0].id)
        XCTAssertEqual(FilePanelState(url: missing[0].url).message, "このファイルは表示できません")
    }
    func testExistingWebPanelJSONDecodesUnchanged() throws {
        let json = """
        {"id":"A6A3150E-5935-4DB5-8FA3-4E72C897269F","url":"https://example.invalid","placement":{"x":0.1,"y":0.2,"width":0.3,"height":0.4}}
        """
        let panel = try JSONDecoder().decode(PanelRecord.self, from: Data(json.utf8))
        XCTAssertEqual(PanelSource.classify(panel.url), .web(panel.url))
    }
    func testFilePanelsPreserveSharedBaseWhenPresentationWasFitted() throws {
        let storage = MemorySettingsStorage(), screen = CGSize(width: 600, height: 400)
        let store = SettingsStore(storage: storage)
        let original = record(try fixture("shared.html"))
        store.panels = [original]; store.sharedLayoutReferenceSize = CGSize(width: 1000, height: 800)
        var displayed = original
        displayed.placement = FractionalFrame(frame: CGRect(x: 0, y: 0, width: 288, height: 202), screen: screen)
        store.savePresentedLayout(DisplayLayout(panels: [displayed], referenceSize: screen), for: "uuid:fixture", wasFitted: true)
        XCTAssertEqual(store.panels[0].placement, original.placement)
        XCTAssertEqual(store.panels[0].url, original.url)
    }
    func testDocumentDeclarationsAreAlternateViewers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Sheerpane/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertEqual(Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }), Set(["public.pdf", "public.html", "public.xhtml"]))
        for type in types {
            XCTAssertEqual(type["CFBundleTypeRole"] as? String, "Viewer")
            XCTAssertEqual(type["LSHandlerRank"] as? String, "Alternate")
        }
    }
    func testUnreadablePanelContentIsCenteredWithoutPresentingWindow() throws {
        let unsupported = try fixture("unsupported.txt")
        let first = record(unsupported), second = record(unsupported)
        XCTAssertNotEqual(first.id, second.id)
        let state = FilePanelState(url: second.url)
        let content = FilePanelErrorView(frame: CGRect(x: 7, y: 7, width: 466, height: 293))
        content.apply(state)
        content.needsLayout = true; content.layoutSubtreeIfNeeded()
        XCTAssertEqual(content.messageLabel.stringValue, state.message)
        XCTAssertEqual(content.messageLabel.alignment, .center)
        XCTAssertEqual(content.messageLabel.frame.midY, content.bounds.midY)
        XCTAssertEqual(content.messageLabel.frame.midX, content.bounds.midX)
        XCTAssertNil(content.window)
        XCTAssertEqual(content.subviews.count, 2)
        XCTAssertEqual(content.reasonLabel.stringValue, "PDF と HTML のファイルを開けます。")
        XCTAssertFalse(content.reasonLabel.isHidden)
        XCTAssertEqual(content.reasonLabel.alignment, .center)
        XCTAssertEqual(content.reasonLabel.frame.midX, content.bounds.midX)
        XCTAssertLessThan(content.reasonLabel.frame.maxY, content.messageLabel.frame.minY)
    }
}
