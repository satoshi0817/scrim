import SwiftUI
import ScrimCore

struct PanelThemeSettingsView: View {
    private enum Mode: String, CaseIterable { case light = "ライト", dark = "ダーク" }
    private enum Target: String, CaseIterable { case background = "背景", highlight = "ハイライト" }
    let store: SettingsStore
    @ObservedObject private var theme = ScrimTheme.shared
    @State private var hex = ""
    @State private var mode = Mode.light
    @State private var target = Target.highlight
    private let presets: [(name: String, rgb: UInt32)] = [
        ("青", SettingsStore.defaultAccentRGB), ("水色", 0x1DA6CC),
        ("緑", 0x2D9A57), ("黄", 0xD7A10B),
        ("オレンジ", 0xE37B2D), ("赤", 0xDD4C58),
        ("ピンク", 0xD7549B), ("紫", 0x8966D7)
    ]

    var body: some View {
        ForEach(PanelThemePreset.allCases, id: \.self) { preset in
            let selected = theme.settings.preset == preset
            let pair = theme.settings[preset]
            Button {
                update { $0.preset = preset }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(title(preset)).fontWeight(.medium)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? theme.accent.ink : .secondary)
                    }
                    HStack(spacing: 8) {
                        sample(.light, colors: pair.light)
                        sample(.dark, colors: pair.dark)
                    }
                }
                .padding(8)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title(preset))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        DisclosureGroup("選択したテーマを編集") {
            Picker("外観", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("編集する色", selection: $target) {
                ForEach(Target.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if target == .highlight { swatches }
            HStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: ScrimAccent.color(rgb: rgb)))
                    .frame(width: 24, height: 24)
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.18)) }
                    .accessibilityHidden(true)
                TextField("#RRGGBB", text: $hex)
                    .font(.system(.body, design: .monospaced)).frame(width: 100)
                    .accessibilityLabel("カラーコード")
                    .onSubmit(applyHex)
                Button("適用", action: applyHex).disabled(hexRGB == nil)
                Spacer()
                Button("テーマの色を戻す") {
                    update { settings in settings[settings.preset] = settings.preset.colors }
                }.disabled(theme.settings[theme.settings.preset] == theme.settings.preset.colors)
            }
            component("赤", shift: 16)
            component("緑", shift: 8)
            component("青", shift: 0)
            Text("読みやすさを保つため、背景の明るさとハイライトのコントラストを調整します。上の見本に実際の色が反映されます。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: rgb, initial: true) { _, value in hex = String(format: "#%06X", value) }
        .onChange(of: mode) { _, _ in hex = String(format: "#%06X", rgb) }
        .onChange(of: target) { _, _ in hex = String(format: "#%06X", rgb) }
        .onChange(of: theme.settings.preset) { _, _ in hex = String(format: "#%06X", rgb) }
    }

    private func title(_ preset: PanelThemePreset) -> String {
        switch preset {
        case .neutral: "ニュートラル"
        case .warm: "暖色"
        case .cool: "寒色"
        }
    }

    private func sample(_ mode: Mode, colors: PanelThemeColors) -> some View {
        let accent = ScrimAccent(colors: colors, dark: mode == .dark)
        return VStack(alignment: .leading, spacing: 5) {
            Text(mode.rawValue).font(.system(size: 11, weight: .medium))
            Label("ハイライト", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent.ink)
        }
        .foregroundStyle(mode == .dark ? Color.white : Color.black)
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.14)) }
        .accessibilityHidden(true)
    }

    private var swatches: some View {
        HStack(spacing: 9) {
            ForEach(presets, id: \.rgb) { preset in
                let selected = rgb == preset.rgb
                Button { select(preset.rgb) } label: {
                    Circle()
                        .fill(Color(nsColor: ScrimAccent.color(rgb: preset.rgb)))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.black.opacity(0.75), in: Circle())
                            }
                        }
                        .padding(3)
                        .overlay { Circle().strokeBorder(.primary.opacity(selected ? 0.8 : 0.12)) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(preset.name)
            }
        }
    }

    private var colorKey: WritableKeyPath<PanelThemePair, UInt32> {
        switch (mode, target) {
        case (.light, .background): \.light.background
        case (.light, .highlight): \.light.highlight
        case (.dark, .background): \.dark.background
        case (.dark, .highlight): \.dark.highlight
        }
    }

    private var rgb: UInt32 { theme.settings[theme.settings.preset][keyPath: colorKey] }

    private var hexRGB: UInt32? {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.utf8.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return UInt32(digits, radix: 16)
    }

    private func applyHex() {
        if let hexRGB { select(hexRGB) }
    }

    private func component(_ label: String, shift: UInt32) -> some View {
        let mask = UInt32(255) << shift
        return Slider(value: Binding(
            get: { Double((rgb & mask) >> shift) },
            set: { value in select((rgb & ~mask) | (UInt32(value) << shift)) }
        ), in: 0...255, step: 1) { Text(label) }
    }

    private func select(_ rgb: UInt32) {
        update { settings in
            let preset = settings.preset
            settings[preset][keyPath: colorKey] = rgb
        }
        hex = String(format: "#%06X", rgb)
    }

    private func update(_ change: (inout PanelThemeSettings) -> Void) {
        var settings = theme.settings
        change(&settings)
        store.panelTheme = settings
        theme.apply(settings)
    }
}
