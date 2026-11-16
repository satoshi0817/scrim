import Foundation

/// A domain snapshot excludes registration defaults and unrelated global preferences.
public protocol SettingsMigrationSource: AnyObject {
    func snapshot() -> [String: Any]
}
public protocol SettingsMigrationStorage: SettingsMigrationSource {
    func set(_ value: Any, forKey key: String)
}

public final class UserDefaultsMigrationSource: SettingsMigrationSource {
    private let defaults: UserDefaults
    private let domain: String
    public init(defaults: UserDefaults, domain: String) {
        self.defaults = defaults
        self.domain = domain
    }
    public func snapshot() -> [String: Any] { defaults.persistentDomain(forName: domain) ?? [:] }
}

public final class UserDefaultsMigrationStorage: SettingsMigrationStorage {
    private let defaults: UserDefaults
    private let source: UserDefaultsMigrationSource
    public init(defaults: UserDefaults, domain: String) {
        self.defaults = defaults
        source = UserDefaultsMigrationSource(defaults: defaults, domain: domain)
    }
    public func snapshot() -> [String: Any] { source.snapshot() }
    public func set(_ value: Any, forKey key: String) { defaults.set(value, forKey: key) }
}

public enum SettingsMigration {
    public static let legacyDomain = "com.satoshi0817.Chira"
    public static let destinationDomain = "com.satoshi0817.Sheerpane"
    public static let migratedKey = "sheerpaneSettingsMigrated"

    /// An explicit test-copy override never consults the legacy domain.
    public static func shouldMigrate(environment: [String: String]) -> Bool {
        environment["SHEERPANE_DEFAULTS_SUITE"] == nil
    }

    public static func migrate(source: SettingsMigrationSource, destination: SettingsMigrationStorage) {
        let existing = destination.snapshot()
        guard existing[migratedKey] as? Bool != true else { return }
        for (key, value) in source.snapshot() where key != migratedKey && existing[key] == nil {
            destination.set(value, forKey: key)
        }
        destination.set(true, forKey: migratedKey)
    }
}
