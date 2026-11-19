import AppKit
import XCTest
import ScrimAssets
@testable import ScrimCore

final class IconResourceTests: XCTestCase {
    func testSwiftPMBundleContainsLoadableDesignerIcons() throws {
        for (name, ext) in [("MenuBarTemplate", "pdf"), ("MenuBarWarningTemplate", "pdf"), ("AppIcon", "icns")] {
            let url = try XCTUnwrap(StatusIcon.resourceBundle.url(forResource: name, withExtension: ext))
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertFalse(image.representations.isEmpty, "\(name).\(ext)")
        }
    }

    func testBothMenuImagesLoadAsEighteenPointAccessibleTemplates() {
        for warning in [false, true] {
            let image = StatusIcon.image(warning: warning)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertEqual(image.accessibilityDescription, "Scrim")
            XCTAssertFalse(image.representations.isEmpty)
        }
    }

    func testEveryRegistrationFailureSelectsWarningAndRecoverySelectsNormal() {
        for status in [HotkeyRegistrationStatus.carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus),
                       .carbonFailure(shortcut: .testCopy, status: RegistrationFeedback.internalFailureStatus),
                       .modifierUnavailable(side: .rightOption)] {
            let state = EntryState(shortcut: .default, registration: status)
            XCTAssertEqual(StatusIcon.resourceName(warning: state.showsWarning), "MenuBarWarningTemplate")
            XCTAssertTrue(StatusIcon.image(warning: state.showsWarning).isTemplate)
        }
        XCTAssertEqual(StatusIcon.resourceName(warning: EntryState(shortcut: .default).showsWarning), "MenuBarTemplate")
    }

    func testAppBundleResourcesLoadBeforeSwiftPMFallbackWithoutLaunchingApp() throws {
        // A unique fixture bundle, not an application process or a preferences suite.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scrim-icons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("IconFixture.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.scrim.icons.\(UUID().uuidString)",
                                  "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon.icns"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        for (name, ext) in [("MenuBarTemplate", "pdf"), ("MenuBarWarningTemplate", "pdf"), ("AppIcon", "icns")] {
            let source = try XCTUnwrap(StatusIcon.resourceBundle.url(forResource: name, withExtension: ext))
            try FileManager.default.copyItem(at: source, to: resources.appendingPathComponent("\(name).\(ext)"))
        }
        let bundle = try XCTUnwrap(Bundle(url: app))
        for warning in [false, true] {
            let name = StatusIcon.resourceName(warning: warning)
            let url = try XCTUnwrap(StatusIcon.resourceURL(name: name, extension: "pdf", appBundle: bundle))
            XCTAssertEqual(url.standardizedFileURL, resources.appendingPathComponent("\(name).pdf").standardizedFileURL)
            XCTAssertTrue(StatusIcon.image(warning: warning, appBundle: bundle).isTemplate)
        }
        let iconURL = try XCTUnwrap(bundle.url(forResource: "AppIcon", withExtension: "icns"))
        XCTAssertNotNil(NSImage(contentsOf: iconURL))
    }
}
