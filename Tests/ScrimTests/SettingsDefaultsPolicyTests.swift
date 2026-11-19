import XCTest
@testable import ScrimCore

final class SettingsDefaultsPolicyTests: XCTestCase {
    func testShippingSuiteSuccessDoesNotAccessStandard() {
        let suite = MemorySettingsStorage()
        var requestedSuites: [String] = []
        var standardCalls = 0
        let result = SettingsDefaultsPolicy.open(environment: [:], openSuite: { name in
            requestedSuites.append(name)
            return suite
        }, standard: {
            standardCalls += 1
            return MemorySettingsStorage()
        })
        XCTAssertTrue(result === suite)
        XCTAssertEqual(requestedSuites, [SettingsMigration.destinationDomain])
        XCTAssertEqual(standardCalls, 0)
        XCTAssertTrue(SettingsMigration.shouldMigrate(environment: [:]))
    }

    func testShippingSuiteFailureFallsBackToStandardAfterSuiteAttempt() throws {
        let standard = MemorySettingsStorage()
        var calls: [String] = []
        let result = SettingsDefaultsPolicy.open(environment: [:], openSuite: { name -> MemorySettingsStorage? in
            calls.append(name)
            return nil
        }, standard: {
            calls.append("standard")
            return standard
        })
        XCTAssertTrue(result === standard)
        XCTAssertEqual(calls, [SettingsMigration.destinationDomain, "standard"])
        // The returned object is the storage used for subsequent settings writes.
        SettingsStore(storage: try XCTUnwrap(result)).guided = true
        XCTAssertTrue(SettingsStore(storage: standard).guided)
        XCTAssertTrue(SettingsMigration.shouldMigrate(environment: [:]))
    }

    func testExplicitSuiteSuccessRemainsIsolatedAndSkipsMigration() {
        let environment = ["SCRIM_DEFAULTS_SUITE": "memory-test-copy"]
        let suite = MemorySettingsStorage()
        var requestedSuites: [String] = []
        var standardCalls = 0
        let result = SettingsDefaultsPolicy.open(environment: environment, openSuite: { name in
            requestedSuites.append(name)
            return suite
        }, standard: {
            standardCalls += 1
            return MemorySettingsStorage()
        })
        XCTAssertTrue(result === suite)
        XCTAssertEqual(requestedSuites, ["memory-test-copy"])
        XCTAssertEqual(standardCalls, 0)
        XCTAssertFalse(SettingsMigration.shouldMigrate(environment: environment))
    }

    func testAnyExplicitSuiteFailureDoesNotFallBackOrEnableMigration() {
        // Presence of the override controls isolation, not its contents.
        for override in ["memory-test-copy", "", SettingsMigration.destinationDomain] {
            let environment = ["SCRIM_DEFAULTS_SUITE": override]
            var requestedSuites: [String] = []
            var standardCalls = 0
            let result = SettingsDefaultsPolicy.open(environment: environment, openSuite: { name -> MemorySettingsStorage? in
                requestedSuites.append(name)
                return nil
            }, standard: {
                standardCalls += 1
                return MemorySettingsStorage()
            })
            XCTAssertNil(result)
            XCTAssertEqual(requestedSuites, [override])
            XCTAssertEqual(standardCalls, 0)
            XCTAssertFalse(SettingsMigration.shouldMigrate(environment: environment))
        }
    }
}
