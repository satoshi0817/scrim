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
}

public struct DisplayLayout: Codable {
    public var panels: [PanelRecord]
    private var referenceCanvas: LayoutSize
    private enum CodingKeys: String, CodingKey {
        case panels
        case referenceCanvas = "referenceSize"
    }
    public var referenceSize: CGSize {
        get { referenceCanvas.size }
        set { referenceCanvas = LayoutSize(newValue) }
    }
    public init(panels: [PanelRecord], referenceSize: CGSize) {
        self.panels = panels; self.referenceCanvas = LayoutSize(referenceSize)
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
    func layout(for display: String, screen: CGSize, current: DisplayLayout? = nil) -> DisplayLayout {
        if sharedLayoutReferenceSize == nil { sharedLayoutReferenceSize = screen }
        let shared = DisplayLayout(panels: panels, referenceSize: sharedLayoutReferenceSize ?? screen)
        if sameLayoutOnAllDisplays { return shared }
        if let saved = layoutsByDisplay[display] { return saved }
        let copy = current ?? shared
        if !display.hasPrefix("ephemeral:") {
            var layouts = layoutsByDisplay; layouts[display] = copy; layoutsByDisplay = layouts
        }
        return copy
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
    func saveLayout(_ layout: DisplayLayout, for display: String) {
        if sameLayoutOnAllDisplays {
            panels = layout.panels; sharedLayoutReferenceSize = layout.referenceSize
        } else if !display.hasPrefix("ephemeral:") {
            var layouts = layoutsByDisplay; layouts[display] = layout; layoutsByDisplay = layouts
        }
    }
}
public enum LayoutFitter {
    public static let minimumScale: CGFloat = 0.6 // frame preference; never a visual transform
    public static let minimumPanelSize = CGSize(width: 240, height: 160)
    public static let gap: CGFloat = 12
    public static let titleBarHeight: CGFloat = 28
    public static let diagnosticsGap: CGFloat = 20
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
