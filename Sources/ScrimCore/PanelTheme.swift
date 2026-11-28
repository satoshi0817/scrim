public enum PanelThemePreset: String, Codable, CaseIterable {
    case neutral, warm, cool

    public var colors: PanelThemePair {
        switch self {
        case .neutral:
            PanelThemePair(light: .init(background: 0xF5F5F5, highlight: SettingsStore.defaultAccentRGB),
                           dark: .init(background: 0x242426, highlight: SettingsStore.defaultAccentRGB))
        case .warm:
            PanelThemePair(light: .init(background: 0xFBF2E5, highlight: 0xAC5032),
                           dark: .init(background: 0x2B2421, highlight: 0xEE986C))
        case .cool:
            PanelThemePair(light: .init(background: 0xEAF1F6, highlight: 0x256F82),
                           dark: .init(background: 0x1C2934, highlight: 0x64C7D8))
        }
    }
}

public struct PanelThemeColors: Codable, Equatable {
    public var background: UInt32
    public var highlight: UInt32

    public init(background: UInt32, highlight: UInt32) {
        self.background = background
        self.highlight = highlight
    }
}

public struct PanelThemePair: Codable, Equatable {
    public var light: PanelThemeColors
    public var dark: PanelThemeColors
}

public struct PanelThemeSettings: Codable, Equatable {
    public var preset: PanelThemePreset = .neutral
    private var overrides: [PanelThemePreset: PanelThemePair] = [:]

    public init(legacyAccent: UInt32 = SettingsStore.defaultAccentRGB) {
        guard legacyAccent != SettingsStore.defaultAccentRGB else { return }
        var colors = PanelThemePreset.neutral.colors
        colors.light.highlight = legacyAccent
        colors.dark.highlight = legacyAccent
        overrides[.neutral] = colors
    }

    public subscript(_ preset: PanelThemePreset) -> PanelThemePair {
        get { overrides[preset] ?? preset.colors }
        set { overrides[preset] = newValue == preset.colors ? nil : newValue }
    }
}
