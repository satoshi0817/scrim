/// Decides which destination to use without accessing preferences itself.
/// Injected factories let tests cover opening failures using memory objects only.
public enum SettingsDefaultsPolicy {
    public static func open<Storage>(
        environment: [String: String],
        openSuite: (String) -> Storage?,
        standard: () -> Storage
    ) -> Storage? {
        if let override = environment["SCRIM_DEFAULTS_SUITE"] {
            // An explicit override must remain isolated, including on failure.
            return openSuite(override)
        }
        // Foundation rejects the current app's bundle identifier as a suite name.
        // In the bundled app, standard writes to that app's persistent domain.
        return openSuite(SettingsMigration.destinationDomain) ?? standard()
    }
}
