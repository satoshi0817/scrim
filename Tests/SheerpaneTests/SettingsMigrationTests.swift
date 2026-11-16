import XCTest
@testable import SheerpaneCore

final class SettingsMigrationTests: XCTestCase {
    private final class MemoryDomain: SettingsMigrationStorage {
        var values: [String: Any]
        var reads = 0
        var writes = 0
        init(_ values: [String: Any] = [:]) { self.values = values }
        func snapshot() -> [String: Any] { reads += 1; return values }
        func set(_ value: Any, forKey key: String) { writes += 1; values[key] = value }
    }

    func testFirstMigrationCopiesAllStoredKeysWithoutDecoding() throws {
        let shortcut = try JSONEncoder().encode(Shortcut.testCopy)
        let source = MemoryDomain(["shortcut": shortcut, "guided": Data("true".utf8),
                                   "futureSetting": ["enabled": true]])
        let destination = MemoryDomain()
        SettingsMigration.migrate(source: source, destination: destination)
        XCTAssertEqual(destination.values["shortcut"] as? Data, shortcut)
        XCTAssertEqual(destination.values["guided"] as? Data, Data("true".utf8))
        XCTAssertEqual(destination.values["futureSetting"] as? [String: Bool], ["enabled": true])
        XCTAssertEqual(destination.values[SettingsMigration.migratedKey] as? Bool, true)
        XCTAssertEqual(destination.writes, 4)
    }

    func testSecondLaunchDoesNotReadSourceOrWriteDestination() {
        let source = MemoryDomain(["guided": Data("true".utf8)])
        let destination = MemoryDomain()
        SettingsMigration.migrate(source: source, destination: destination)
        source.values["laterSetting"] = Data([1, 2, 3])
        let previousWrites = destination.writes
        SettingsMigration.migrate(source: source, destination: destination)
        XCTAssertEqual(source.reads, 1)
        XCTAssertEqual(destination.writes, previousWrites)
        XCTAssertNil(destination.values["laterSetting"])
    }

    func testEmptySourceStillMarksMigrationComplete() {
        let destination = MemoryDomain()
        SettingsMigration.migrate(source: MemoryDomain(), destination: destination)
        XCTAssertEqual(destination.values.count, 1)
        XCTAssertEqual(destination.values[SettingsMigration.migratedKey] as? Bool, true)
    }

    func testExistingDestinationValuesArePreservedIncludingFalseAndEmptyData() {
        let source = MemoryDomain(["dockVisible": Data("true".utf8), "empty": Data([1]), "flag": true])
        let destination = MemoryDomain(["dockVisible": Data("false".utf8), "empty": Data(), "flag": false])
        SettingsMigration.migrate(source: source, destination: destination)
        XCTAssertEqual(destination.values["dockVisible"] as? Data, Data("false".utf8))
        XCTAssertEqual(destination.values["empty"] as? Data, Data())
        XCTAssertEqual(destination.values["flag"] as? Bool, false)
        XCTAssertEqual(destination.writes, 1)
    }

    func testSourceRemainsContentAndDataByteIdenticalAfterBothLaunches() throws {
        let source = MemoryDomain(["shortcut": Data([0, 255, 128, 1]), "nested": ["items": [1, 2, 3]],
                                   "name": "旧設定", "flag": false])
        let before = NSDictionary(dictionary: source.values)
        let originalBytes = source.values["shortcut"] as? Data
        let destination = MemoryDomain()
        SettingsMigration.migrate(source: source, destination: destination)
        SettingsMigration.migrate(source: source, destination: destination)
        XCTAssertEqual(NSDictionary(dictionary: source.values), before)
        XCTAssertEqual(source.values["shortcut"] as? Data, originalBytes)
        XCTAssertEqual(source.writes, 0)
        XCTAssertNil(source.values[SettingsMigration.migratedKey])
    }

    func testSuiteOverrideSkipsLegacyMigration() {
        XCTAssertTrue(SettingsMigration.shouldMigrate(environment: [:]))
        XCTAssertFalse(SettingsMigration.shouldMigrate(environment: ["SHEERPANE_DEFAULTS_SUITE": "memory-test-copy"]))
    }
}
