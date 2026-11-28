import AppKit
import SwiftUI
import ScrimCore

enum ScrimPalette {
    static let nativeAmber = NSColor(srgbRed: 1, green: 175/255, blue: 0, alpha: 1)
    static let nativeRed = NSColor(srgbRed: 1, green: 50/255, blue: 26/255, alpha: 1)
    static let amber = Color(nsColor: nativeAmber)
    static let red = Color(nsColor: nativeRed)

    static func mix(_ from: NSColor, _ to: NSColor, _ fraction: CGFloat) -> Color {
        Color(nsColor: from.blended(withFraction: min(1, max(0, fraction)), of: to) ?? from)
    }

}

struct ScrimAccent {
    let native: NSColor
    let nativeInk: NSColor
    let nativeButton: NSColor
    let nativeBackground: NSColor
    var ink: Color { Color(nsColor: nativeInk) }
    var button: Color { Color(nsColor: nativeButton) }
    var background: Color { Color(nsColor: nativeBackground) }

    static func color(rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    init(_ pair: PanelThemePair) {
        let light = Self(colors: pair.light, dark: false)
        let dark = Self(colors: pair.dark, dark: true)
        func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        }
        native = adaptive(light.native, dark.native)
        nativeBackground = adaptive(light.nativeBackground, dark.nativeBackground)
        nativeInk = adaptive(light.nativeInk, dark.nativeInk)
        nativeButton = adaptive(light.nativeButton, dark.nativeButton)
    }

    init(colors: PanelThemeColors, dark: Bool) {
        native = Self.color(rgb: colors.highlight)
        // Preserve the system's text hierarchy against any custom background.
        nativeBackground = Self.adjust(Self.color(rgb: colors.background), toward: dark ? .black : .white) {
            dark ? $0 <= 0.10 : $0 >= 0.68
        }
        let surface = Self.luminance(nativeBackground)
        nativeInk = Self.adjust(native, toward: dark ? .white : .black) {
            Self.contrast($0, surface) >= 4.5
        }
        nativeButton = Self.adjust(native, toward: .black) { Self.contrast($0, 1) >= 4.5 }
    }

    static func luminance(_ color: NSColor) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear(color.redComponent) * 0.2126 + linear(color.greenComponent) * 0.7152
            + linear(color.blueComponent) * 0.0722
    }

    static func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func adjust(_ color: NSColor, toward target: NSColor, accepts: (CGFloat) -> Bool) -> NSColor {
        let target = target.usingColorSpace(.sRGB) ?? target
        for step in 0...20 {
            let fraction = CGFloat(step) / 20
            let value = NSColor(srgbRed: color.redComponent + (target.redComponent - color.redComponent) * fraction,
                                green: color.greenComponent + (target.greenComponent - color.greenComponent) * fraction,
                                blue: color.blueComponent + (target.blueComponent - color.blueComponent) * fraction, alpha: 1)
            if accepts(luminance(value)) { return value }
        }
        return target
    }
}

final class ScrimTheme: ObservableObject {
    static let shared = ScrimTheme()
    @Published private(set) var settings = PanelThemeSettings()
    private(set) var accent = ScrimAccent(PanelThemePreset.neutral.colors)

    func apply(_ settings: PanelThemeSettings) {
        guard settings != self.settings else { return }
        accent = ScrimAccent(settings[settings.preset])
        self.settings = settings
    }
}

private struct ScrimAccentKey: EnvironmentKey {
    static let defaultValue = ScrimAccent(PanelThemePreset.neutral.colors)
}

extension EnvironmentValues {
    var scrimAccent: ScrimAccent {
        get { self[ScrimAccentKey.self] }
        set { self[ScrimAccentKey.self] = newValue }
    }
}

private struct ScrimTint: ViewModifier {
    @ObservedObject private var theme = ScrimTheme.shared
    func body(content: Content) -> some View {
        content.tint(theme.accent.ink).environment(\.scrimAccent, theme.accent)
    }
}

extension View {
    func scrimTint() -> some View { modifier(ScrimTint()) }
}

enum ScrimType {
    static func heading(compact: Bool = false) -> Font {
        .system(size: compact ? 16 : 18, weight: .semibold)
    }
    static func body(_ size: CGFloat = 14) -> Font { .system(size: size) }
    static func metadata(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .medium) }
    static func reading(_ size: CGFloat) -> Font { .system(size: size).monospacedDigit() }
}
