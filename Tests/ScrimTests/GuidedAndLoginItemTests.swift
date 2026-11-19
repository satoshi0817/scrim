import XCTest
@testable import ScrimCore

final class GuidedAndLoginItemTests: XCTestCase {
    private final class RawStorage: SettingsStorage, SettingsMigrationStorage {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func setData(_ data: Data?, forKey key: String) { values[key] = data }
        func snapshot() -> [String: Any] { values }
        func set(_ value: Any, forKey key: String) { values[key] = value }
    }
    private final class LegacySnapshot: SettingsMigrationSource {
        let values: [String: Any] = ["guided": Data("true".utf8)]
        func snapshot() -> [String: Any] { values }
    }
    func testGuidedBoolTrue() {
        let storage = RawStorage(); storage.values["guided"] = true
        XCTAssertTrue(SettingsStore(storage: storage).guided)
    }
    func testGuidedUTF8True() {
        let storage = RawStorage(); storage.values["guided"] = Data("true".utf8)
        XCTAssertTrue(SettingsStore(storage: storage).guided)
    }
    func testGuidedStringTrue() {
        let storage = RawStorage(); storage.values["guided"] = "true"
        XCTAssertTrue(SettingsStore(storage: storage).guided)
    }
    func testGuidedJSONBoolAndStringTrue() throws {
        let storage = RawStorage()
        for data in [try JSONEncoder().encode(true), try JSONEncoder().encode("true")] {
            storage.values["guided"] = data
            XCTAssertTrue(SettingsStore(storage: storage).guided)
        }
    }
    func testGuidedFalseMissingAndInvalid() throws {
        let storage = RawStorage()
        XCTAssertFalse(SettingsStore(storage: storage).guided)
        for value: Any in [false, "false", Data("false".utf8), try JSONEncoder().encode("false"), 1, "yes", Data([0xff])] {
            storage.values["guided"] = value
            XCTAssertFalse(SettingsStore(storage: storage).guided)
        }
    }
    // 2回起動しても案内は1回だけ
    func testTwoFreshLaunchesShowGuidanceOnlyOnceAndDismissalRewritesBool() throws {
        let storage = RawStorage()
        let first = SettingsStore(storage: storage)
        XCTAssertTrue(first.beginFirstRunGuidance())
        XCTAssertEqual(try JSONDecoder().decode(Bool.self, from: XCTUnwrap(storage.data(forKey: "guided"))), true)
        storage.values["guided"] = Data("\"true\"".utf8)
        first.finishFirstRunGuidance()
        XCTAssertEqual(storage.data(forKey: "guided"), try JSONEncoder().encode(true))
        XCTAssertFalse(SettingsStore(storage: storage).beginFirstRunGuidance())
    }
    func testTwoLaunchesWithMigratedDataNeverShowGuidance() {
        let source = LegacySnapshot()
        let storage = RawStorage()
        SettingsMigration.migrate(source: source, destination: storage)
        XCTAssertFalse(SettingsStore(storage: storage).beginFirstRunGuidance())
        SettingsMigration.migrate(source: source, destination: storage)
        XCTAssertFalse(SettingsStore(storage: storage).beginFirstRunGuidance())
        XCTAssertEqual(source.values["guided"] as? Data, Data("true".utf8))
    }
    func testLoginDefaultOffAndConstructionHasNoSideEffects() {
        let fake = FakeLoginItemService(); let model = LoginItemSettingsModel(service: fake)
        XCTAssertFalse(model.isOn); XCTAssertFalse(model.showsApproval)
        XCTAssertEqual(fake.registerCalls, 0); XCTAssertEqual(fake.unregisterCalls, 0)
        XCTAssertEqual(fake.settingsCalls, 0)
    }
    func testLoginReflectsLiveStatusChanges() {
        let fake = FakeLoginItemService(); let model = LoginItemSettingsModel(service: fake)
        fake.status = .enabled; XCTAssertTrue(model.isOn)
        fake.status = .notRegistered; XCTAssertFalse(model.isOn)
        fake.status = .notFound; XCTAssertFalse(model.isOn)
        model.setEnabled(true); XCTAssertTrue(model.isOn)
        model.setEnabled(false); XCTAssertFalse(model.isOn)
    }
    func testLoginApprovalCopyAndButtonVisibility() {
        let fake = FakeLoginItemService(status: .requiresApproval)
        let model = LoginItemSettingsModel(service: fake)
        XCTAssertTrue(model.isOn); XCTAssertTrue(model.showsApproval)
        XCTAssertTrue(model.showsSettings)
        XCTAssertEqual(LoginItemSettingsModel.title, "ログイン時に Scrim を開く")
        XCTAssertEqual(LoginItemSettingsModel.approvalText, "システム設定の『ログイン項目』で許可が必要です")
        XCTAssertEqual(LoginItemSettingsModel.settingsTitle, "システム設定を開く")
        model.openSettings(); XCTAssertEqual(fake.settingsCalls, 1)
        fake.status = .enabled; XCTAssertFalse(model.showsApproval)
    }
    func testLoginRegisterAndUnregisterErrorsSurfaceAndRetainLiveStatus() {
        for status in [LoginItemStatus.notRegistered, .enabled] {
            let fake = FakeLoginItemService(status: status)
            fake.failure = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "テストエラー"])
            let model = LoginItemSettingsModel(service: fake)
            model.setEnabled(status == .notRegistered)
            XCTAssertEqual(model.errorText, status == .notRegistered
                ? "ログイン項目に登録できませんでした。システム設定の『ログイン項目』を確認してください。"
                : "ログイン項目から外せませんでした。システム設定の『ログイン項目』を確認してください。")
            XCTAssertEqual(fake.status, status)
            // Settings.refresh assigns this live value back to the checkbox after the click.
            XCTAssertEqual(model.isOn, status == .enabled)
            XCTAssertTrue(model.showsSettings)
            XCTAssertFalse(model.errorText?.contains("テストエラー") ?? true)
            fake.failure = nil; model.setEnabled(status == .notRegistered)
            XCTAssertNil(model.errorText)
            XCTAssertFalse(model.showsSettings)
        }
    }
    func testStoredBoolCannotOverrideLiveLoginStatus() {
        let storage = RawStorage()
        let fake = FakeLoginItemService(); let model = LoginItemSettingsModel(service: fake)
        for key in ["launchAtLogin", "loginItem", "loginEnabled"] { storage.values[key] = true }
        _ = SettingsStore(storage: storage)
        XCTAssertFalse(model.isOn)
        for key in ["launchAtLogin", "loginItem", "loginEnabled"] { storage.values[key] = false }
        fake.status = .enabled
        XCTAssertTrue(model.isOn)
    }
}
