import Foundation
import CoreGraphics
import ColorSync

/// Explicit JSON width/height representation, independent of CGSize's encoding support.
struct LayoutSize: Codable {
    var width: Double
    var height: Double
    init(_ size: CGSize) { width = Double(size.width); height = Double(size.height) }
    var size: CGSize { CGSize(width: width, height: height) }
}

public enum DisplayLayoutCopy {
    public static let checkboxTitle = "すべてのディスプレイで同じ配置"
    public static let sharedFooter = "すべての画面で同じパネルを、画面に対する比率を保って表示します。"
    public static let perDisplayFooter = "パネルの追加・削除やURLはすべての画面で共通です。位置・サイズ・重なり順だけを画面ごとに記憶します。"
    public static let switchFooter = "切り替えると直前の配置を引き継ぎます。オンに戻すと、最後にパネルを追加・削除・移動した画面の配置が共通になります。"
    public static let visibilityHeader = "表示するディスプレイ"
    public static let visibilityFooter = "オフにした画面にポインタがあるときは、ジェスチャーやショートカットで呼び出しても開きません。メニューバーから開く操作は、オンの画面に表示します。"
}

/// In per-display mode, a saved layout supplies only order and geometry; content comes from the shared panels.
public struct DisplayLayout: Codable {
    public var panels: [PanelRecord]
    private var referenceCanvas: LayoutSize
    /// Last time this display's panel set or geometry changed; picks the arrangement kept when sharing again.
    public var editedAt: Date?
    private enum CodingKeys: String, CodingKey {
        case panels
        case referenceCanvas = "referenceSize"
        case editedAt
    }
    public var referenceSize: CGSize {
        get { referenceCanvas.size }
        set { referenceCanvas = LayoutSize(newValue) }
    }
    public init(panels: [PanelRecord], referenceSize: CGSize, editedAt: Date? = nil) {
        self.panels = panels; self.referenceCanvas = LayoutSize(referenceSize); self.editedAt = editedAt
    }
    /// Shared content in this arrangement's order and geometry. Panels it has not seen yet
    /// follow in shared order, at their shared fractions of this arrangement's screen.
    public static func merging(content: [PanelRecord], arrangement: DisplayLayout) -> DisplayLayout {
        let shared = Dictionary(content.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var panels = arrangement.panels.compactMap { arranged -> PanelRecord? in
            guard var record = shared[arranged.id], seen.insert(arranged.id).inserted else { return nil }
            record.placement = arranged.placement; return record
        }
        panels += content.filter { !seen.contains($0.id) }
        return DisplayLayout(panels: panels, referenceSize: arrangement.referenceSize, editedAt: arrangement.editedAt)
    }
    /// True when the same panels sit at the same fractions. Stacking order is ignored, because
    /// clicking a panel brings it forward without the user rearranging anything.
    /// Placements round-trip through view frames, so compare them with a small tolerance.
    func hasSameArrangement(as other: DisplayLayout) -> Bool {
        let theirs = Dictionary(other.panels.map { ($0.id, $0.placement) }, uniquingKeysWith: { first, _ in first })
        guard panels.count == other.panels.count, Set(panels.map(\.id)) == Set(theirs.keys) else { return false }
        return panels.allSatisfy { panel in
            guard let q = theirs[panel.id] else { return false }
            let p = panel.placement
            return [p.x - q.x, p.y - q.y, p.width - q.width, p.height - q.height].allSatisfy { abs($0) < 1e-6 }
        }
    }
}
public protocol DisplayUUIDProviding {
    func uuid(for displayID: CGDirectDisplayID) -> String?
}
public struct CoreGraphicsDisplayUUIDProvider: DisplayUUIDProviding {
    public init() {}
    public func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }
}
public final class DisplayIdentity {
    private let provider: DisplayUUIDProviding
    private var fallback: [CGDirectDisplayID: String] = [:]
    public init(provider: DisplayUUIDProviding = CoreGraphicsDisplayUUIDProvider()) { self.provider = provider }
    public func key(for id: CGDirectDisplayID) -> String {
        if let uuid = provider.uuid(for: id) { return "uuid:" + uuid.lowercased() }
        if let key = fallback[id] { return key }
        let key = "ephemeral:" + UUID().uuidString
        fallback[id] = key; return key
    }
    public func forgetUnavailable(connected: Set<CGDirectDisplayID>) {
        fallback = fallback.filter { connected.contains($0.key) }
    }
}
public extension SettingsStore {
    /// Adopt the first presentation screen for legacy fractions without rewriting them.
    /// `transient` is an in-memory arrangement for a display without a stable UUID.
    func layout(for display: String, screen: CGSize, transient: DisplayLayout? = nil) -> DisplayLayout {
        if sharedLayoutReferenceSize == nil { sharedLayoutReferenceSize = screen }
        if sameLayoutOnAllDisplays { return DisplayLayout(panels: panels, referenceSize: sharedLayoutReferenceSize ?? screen) }
        // A display without its own arrangement starts from the shared one, as it looked on this screen.
        guard let arrangement = transient ?? layoutsByDisplay[display] else { return DisplayLayout(panels: panels, referenceSize: screen) }
        return DisplayLayout.merging(content: panels, arrangement: arrangement)
    }
    func showsOverlay(on display: String) -> Bool { !disabledDisplays.contains(display) }
    func setShowsOverlay(_ shows: Bool, on display: String) {
        guard !display.hasPrefix("ephemeral:") else { return }
        var disabled = disabledDisplays
        if shows { disabled.remove(display) } else { disabled.insert(display) }
        disabledDisplays = disabled
    }
    /// Switching carries over what was shown last. Turning per-display layouts on starts every
    /// display from the shared layout; turning them off adopts the most recently edited display's.
    func setSameLayoutOnAllDisplays(_ value: Bool) {
        guard value != sameLayoutOnAllDisplays else { return }
        for page in 0..<pageCount {
            let layoutsKey = pageKey("layoutsByDisplay", page: page)
            if value {
                let layouts: [String: DisplayLayout] = read(layoutsKey, fallback: [:])
                let edited = layouts.values.compactMap { layout in layout.editedAt.map { (layout, $0) } }
                if let latest = edited.max(by: { $0.1 < $1.1 })?.0 {
                    let content: [PanelRecord] = read(pageKey("panels", page: page), fallback: [])
                    let adopted = DisplayLayout.merging(content: content, arrangement: latest)
                    write(adopted.panels, pageKey("panels", page: page))
                    write(LayoutSize(adopted.referenceSize), pageKey("sharedLayoutReferenceSize", page: page))
                }
            }
            write([String: DisplayLayout](), layoutsKey)
        }
        sameLayoutOnAllDisplays = value
    }
    /// Before per-display layouts shared their content, each display kept its own panel list.
    /// Keep every panel any display still had by adding it to the shared list once.
    func shareLegacyDisplayContent() {
        guard !read("displayContentShared", fallback: false) else { return }
        if !sameLayoutOnAllDisplays {
            for page in 0..<pageCount {
                let layouts: [String: DisplayLayout] = read(pageKey("layoutsByDisplay", page: page), fallback: [:])
                var content: [PanelRecord] = read(pageKey("panels", page: page), fallback: [])
                var known = Set(content.map(\.id))
                for key in layouts.keys.sorted() {
                    for panel in layouts[key]?.panels ?? [] where known.insert(panel.id).inserted { content.append(panel) }
                }
                write(Array(content.prefix(PanelPool.maximum)), pageKey("panels", page: page))
            }
        }
        write(true, "displayContentShared")
    }
    /// Fitted shared presentations save order and metadata, never computed geometry.
    func savePresentedLayout(_ shown: DisplayLayout, for display: String, wasFitted: Bool) {
        guard sameLayoutOnAllDisplays && wasFitted else { saveLayout(shown, for: display); return }
        let reference = sharedLayoutReferenceSize ?? shown.referenceSize
        let originals = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0.placement) })
        panels = shown.panels.map { panel in
            var copy = panel
            if let placement = originals[panel.id] { copy.placement = placement }
            else {
                let p = panel.placement, s = shown.referenceSize
                copy.placement = FractionalFrame(frame: CGRect(x: p.x*s.width, y: p.y*s.height,
                    width: p.width*s.width, height: p.height*s.height), screen: reference)
            }
            return copy
        }
    }
    /// Per-display saves write content to the shared panels and order/geometry to this display only.
    func saveLayout(_ layout: DisplayLayout, for display: String) {
        if sameLayoutOnAllDisplays {
            panels = layout.panels; sharedLayoutReferenceSize = layout.referenceSize; return
        }
        let previousContent = panels
        let shown = Dictionary(layout.panels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Shared geometry stays as it was; panels new to the shared list keep this display's fractions.
        var content = previousContent.compactMap { old -> PanelRecord? in
            guard var record = shown[old.id] else { return nil }
            record.placement = old.placement; return record
        }
        let known = Set(previousContent.map(\.id))
        content += layout.panels.filter { !known.contains($0.id) }
        panels = content
        var layouts = layoutsByDisplay
        if !display.hasPrefix("ephemeral:") {
            let baseline = layouts[display] ?? DisplayLayout(panels: previousContent, referenceSize: layout.referenceSize)
            var arrangement = layout
            arrangement.editedAt = baseline.hasSameArrangement(as: layout) ? baseline.editedAt : Date()
            layouts[display] = arrangement
        }
        // Removing a panel on one display removes it everywhere.
        let ids = Set(content.map(\.id))
        for key in layouts.keys { layouts[key]?.panels.removeAll { !ids.contains($0.id) } }
        layoutsByDisplay = layouts
    }
}
public enum LayoutFitter {
    public static let minimumScale: CGFloat = 0.6 // frame preference; never a visual transform
    public static let minimumPanelSize = CGSize(width: 240, height: 160)
    public static let gap: CGFloat = 12
    public static let titleBarHeight: CGFloat = 28
    public static let diagnosticsGap: CGFloat = 20
    /// Shared layouts preserve each panel's position and size as screen fractions.
    /// Never pack in record order: that order changes when a panel is brought forward.
    public static func relativeFrames(layout: DisplayLayout, screen: CGSize) -> [CGRect] {
        guard screen.width > 0, screen.height > 0 else { return [] }
        return layout.panels.map { panel in
            let p = panel.placement
            let width = min(screen.width, max(1, p.width * screen.width))
            let height = min(screen.height, max(1, p.height * screen.height))
            return CGRect(x: min(max(0, p.x * screen.width), screen.width-width),
                          y: min(max(0, p.y * screen.height), screen.height-height), width: width, height: height)
        }
    }
    public static func canonicalFrames(layout: DisplayLayout) -> [CGRect] {
        layout.panels.map {
            let p = $0.placement, s = layout.referenceSize
            return CGRect(x: p.x*s.width, y: p.y*s.height, width: p.width*s.width, height: p.height*s.height)
        }
    }
    public static func needsFitting(layout: DisplayLayout, screen: CGSize) -> Bool {
        frames(layout: layout, screen: screen) != canonicalFrames(layout: layout)
    }
    /// Frames resize and content reflows; typography and chrome never scale.
    public static func frames(layout: DisplayLayout, screen: CGSize) -> [CGRect] {
        guard screen.width > 0, screen.height > 0 else { return [] }
        let source = canonicalFrames(layout: layout)
        let bounds = CGRect(origin: .zero, size: screen)
        if source.allSatisfy({ bounds.contains($0) }) { return source }
        let sizes = source.map { r in
            CGSize(width: min(screen.width, min(r.width, max(minimumPanelSize.width, r.width*minimumScale))),
                   height: min(screen.height, min(r.height, max(minimumPanelSize.height, r.height*minimumScale))))
        }
        var result: [CGRect] = []
        var x: CGFloat = 0, top = screen.height, rowHeight: CGFloat = 0
        for size in sizes {
            if x > 0 && x+size.width > screen.width {
                top -= rowHeight+gap; x = 0; rowHeight = 0
            }
            result.append(CGRect(x: x, y: top-size.height, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height); x += size.width+gap
        }
        if result.allSatisfy({ bounds.contains($0) }) { return result }
        // Later panels draw above earlier ones. Each successive top edge is one
        // title bar lower, exposing a clickable strip. If n*28 exceeds screen
        // height, expose screen.height/n instead; full strips are impossible.
        let step = min(titleBarHeight, screen.height/CGFloat(max(1, sizes.count)))
        let availableHeight = screen.height-CGFloat(max(0, sizes.count-1))*step
        return sizes.enumerated().map { index, size in
            let height = min(size.height, availableHeight)
            return CGRect(x: 0, y: screen.height-CGFloat(index)*step-height, width: size.width, height: height)
        }
    }
}
