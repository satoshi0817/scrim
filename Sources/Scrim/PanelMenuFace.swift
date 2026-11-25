import AppKit
import SwiftUI
import CoreImage
import ScrimCore

/// One command in a panel's settings.
struct PanelMenuItem: Identifiable {
    let tag: Int
    let title: String
    let symbol: String
    var destructive = false
    var id: Int { tag }
}

/// Settings and commands for a single panel.
@MainActor final class PanelMenuModel: ObservableObject {
    let title: String
    let actions: [PanelMenuItem]
    let remove: PanelMenuItem
    /// Clock panels only.
    @Published var clockStyle: ClockStyle?
    @Published var digitalZones: [String]
    @Published var zoneQuery = ""
    var choose: (Int) -> Void = { _ in }
    var toggleZone: (String) -> Void = { _ in }
    var close: () -> Void = {}

    init(title: String, actions: [PanelMenuItem], remove: PanelMenuItem,
         clockStyle: ClockStyle? = nil, digitalZones: [String] = []) {
        self.title = title; self.actions = actions; self.remove = remove
        self.clockStyle = clockStyle; self.digitalZones = digitalZones
    }
    var commonZones: [String] { Set(WorkCity.names.keys).union(digitalZones).sorted() }
    /// Up to 30 other zones whose identifier or city name contains the query.
    var otherZones: [String] {
        let query = zoneQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let common = Set(commonZones)
        return TimeZone.knownTimeZoneIdentifiers.filter { !common.contains($0) && $0.lowercased().contains(query) }.sorted().prefix(30).map { $0 }
    }
    static func zoneName(_ id: String) -> String {
        WorkCity.names[id] ?? id.components(separatedBy: "/").last!.replacingOccurrences(of: "_", with: " ")
    }
}

/// A panel's settings and commands in the centered overlay.
struct PanelMenuFace: View {
    @ObservedObject var model: PanelMenuModel
    var settings: AnyView?
    var notion: NotionTasksModel?
    var showsActions: Bool
    let store: SettingsStore
    @State private var showingActions = false

    var body: some View {
        PanelSettingsSurface(title: model.title, closeTitle: notion == nil ? "完了" : "閉じる", close: model.close) {
            if let notion {
                NotionTasksSetupView(model: notion, actions: showsActions ? AnyView(actions) : nil, textSizeStore: store)
            } else if settings != nil || model.clockStyle != nil {
                Picker("パネル設定のタブ", selection: $showingActions) {
                    Text("設定").tag(false)
                    Text("操作").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                if showingActions { actions }
                else if let settings { settings }
                else {
                    ScrollView {
                        clockSection.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }
            } else {
                actions
            }
        }
    }

    private var actions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.actions) { row($0) }
                Divider().padding(.vertical, 6)
                row(model.remove)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ item: PanelMenuItem) -> some View {
        PanelMenuRow(item: item) { model.choose(item.tag) }
    }

    @ViewBuilder private var clockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("時計", selection: Binding(get: { model.clockStyle ?? .analog }, set: { style in
                model.clockStyle = style; model.choose(style == .analog ? 20 : 21)
            })) {
                Text("アナログ").tag(ClockStyle.analog)
                Text("デジタル").tag(ClockStyle.digital)
            }
            .pickerStyle(.segmented).labelsHidden()
            if model.clockStyle == .digital {
                Text("表示するタイムゾーン").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(model.commonZones, id: \.self) { zoneToggle($0) }
                TextField("その他のタイムゾーンを検索", text: $model.zoneQuery).textFieldStyle(.roundedBorder).controlSize(.small)
                ForEach(model.otherZones, id: \.self) { zoneToggle($0) }
            }
        }
    }
    private func zoneToggle(_ id: String) -> some View {
        let selected = model.digitalZones.contains(id)
        return Toggle(isOn: Binding(get: { selected }, set: { _ in model.toggleZone(id) })) {
            Text(PanelMenuModel.zoneName(id)).font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        // The last zone cannot be removed.
        .disabled(selected && model.digitalZones.count == 1)
    }
}

private struct PanelMenuRow: View {
    let item: PanelMenuItem
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Label(item.title, systemImage: item.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.destructive ? ScrimPalette.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A Gaussian-blurred snapshot of the panel, shown under the menu pill while hovered: shapes stay visible,
/// text becomes unreadable. Static on purpose; edit mode does not need live content.
final class PanelBlurView: NSView {
    /// Blur radius in points.
    static let radius: CGFloat = 6
    /// Snapshots are taken at this fraction of point size: blurred output looks the same, at a fraction of the memory.
    static let captureScale: CGFloat = 0.25
    private let imageView = NSImageView()
    private let tint = NSView()
    /// CPU rendering: the images are tiny, and a GPU context would keep surfaces cached.
    private static let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    var hasSnapshot: Bool { imageView.image != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageView.imageScaling = .scaleAxesIndependently
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        addSubview(imageView); addSubview(tint)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); imageView.frame = bounds; tint.frame = bounds }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setSnapshot(_ bitmap: NSBitmapImageRep?) {
        imageView.image = bitmap.flatMap(Self.blurred)
    }
    private static func blurred(_ bitmap: NSBitmapImageRep) -> NSImage? {
        guard let cgImage = bitmap.cgImage, bitmap.size.width > 0 else { return nil }
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius * scale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let result = context.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: result, size: bitmap.size)
    }
}
