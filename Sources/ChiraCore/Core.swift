import Foundation
import CoreGraphics

public enum OverlayState: Equatable { case hidden, peek, pinned
    public var ignoresMouse: Bool { self != .pinned }
    public var needsKey: Bool { self == .pinned }
}
public struct HoldTapStateMachine {
    public static let threshold = 0.25
    public private(set) var state: OverlayState = .hidden
    private var began: Double?
    private var closing = false
    public init() {}
    public mutating func press(at time: Double, toggle: Bool = false) {
        guard began == nil else { return }
        closing = state == .pinned
        if toggle { state = closing ? .hidden : .pinned; return }
        began = time; state = closing ? .hidden : .peek
    }
    public mutating func release(at time: Double) {
        guard let start = began else { return }
        state = !closing && time >= start && time-start < Self.threshold ? .pinned : .hidden
        began = nil
    }
    public mutating func dismiss() { state = .hidden; began = nil }
    public mutating func fallback() { began = nil; state = .pinned }
}
public enum ModifierSide: String, Codable, CaseIterable {
    case leftCommand, rightCommand, leftOption, rightOption, leftControl, rightControl, leftShift, rightShift
    public var mask: UInt64 { [0x08,0x10,0x20,0x40,0x01,0x2000,0x02,0x04][Self.allCases.firstIndex(of: self)!] }
    public var keyCode: UInt16 { [55,54,58,61,59,62,56,60][Self.allCases.firstIndex(of: self)!] }
    public static func from(keyCode: UInt16) -> Self? { allCases.first { $0.keyCode == keyCode } }
    public static func pressed(rawFlags: UInt64) -> Set<Self> { Set(allCases.filter { rawFlags & $0.mask != 0 }) }
}
public enum InputMethod: String, Codable, CaseIterable { case carbon, flagsPoll, eventTap }
public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32 = 45, modifiers: UInt32 = 0x1000 | 0x0800) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let testCopy = Shortcut(keyCode: 80, modifiers: 0x1000 | 0x0800 | 0x0100)
}
/// Fractions of the full NSScreen.frame, using bottom-left screen-local coordinates.
public struct FractionalFrame: Codable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(frame: CGRect, screen: CGSize) {
        x = frame.minX / max(1, screen.width); y = frame.minY / max(1, screen.height)
        width = frame.width / max(1, screen.width); height = frame.height / max(1, screen.height)
    }
    public func restore(screen: CGSize) -> CGRect {
        Placement.constrain(CGRect(x: x*screen.width, y: y*screen.height, width: width*screen.width, height: height*screen.height), screen: screen)
    }
}
public enum Placement {
    public static let grid: CGFloat = 8
    public static let snapThreshold: CGFloat = 10
    public static let visible: CGFloat = 40
    public static func constrain(_ rect: CGRect, screen: CGSize, others: [CGRect] = []) -> CGRect {
        func rounded(_ n: CGFloat) -> CGFloat { (n/grid).rounded()*grid }
        var r = CGRect(x: rounded(rect.minX), y: rounded(rect.minY), width: max(240, rounded(rect.width)), height: max(160, rounded(rect.height)))
        for other in others {
            for edge in [other.minX, other.maxX] {
                if abs(r.minX-edge) <= snapThreshold { r.origin.x = edge }
                else if abs(r.maxX-edge) <= snapThreshold { r.origin.x = edge-r.width }
            }
            for edge in [other.minY, other.maxY] {
                if abs(r.minY-edge) <= snapThreshold { r.origin.y = edge }
                else if abs(r.maxY-edge) <= snapThreshold { r.origin.y = edge-r.height }
            }
        }
        r.origin.x = min(max(r.minX, visible-r.width), max(0, screen.width-visible))
        r.origin.y = min(max(r.minY, visible-r.height), max(0, screen.height-visible))
        return r
    }
}
public struct PanelRecord: Codable, Identifiable {
    public var id: UUID; public var url: URL; public var placement: FractionalFrame
    public init(id: UUID = UUID(), url: URL, placement: FractionalFrame) { self.id = id; self.url = url; self.placement = placement }
}
public struct PanelPool {
    public static let liveLimit = 4
    public static let maximum = 12
    public struct Entry {
        public let id: UUID
        public fileprivate(set) var webViewGeneration = 0
        public fileprivate(set) var live = false
    }
    public private(set) var entries: [Entry] = []
    private var recency: [UUID] = []
    public init() {}
    @discardableResult public mutating func add(_ id: UUID) -> Bool {
        guard entries.count < Self.maximum, !entries.contains(where: { $0.id == id }) else { return false }
        entries.append(Entry(id: id)); view(id); return true
    }
    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id }; recency.removeAll { $0 == id } }
    public mutating func view(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if !entries[index].live { entries[index].webViewGeneration += 1; entries[index].live = true }
        recency.removeAll { $0 == id }; recency.append(id)
        let liveIDs = Set(recency.suffix(Self.liveLimit))
        for i in entries.indices { entries[i].live = liveIDs.contains(entries[i].id) }
    }
}
public final class SettingsStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private func read<T: Decodable>(_ key: String, fallback: T) -> T { guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }; return value }
    private func write<T: Encodable>(_ value: T, _ key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
    public var shortcut: Shortcut { get { read("shortcut", fallback: Shortcut()) } set { write(newValue, "shortcut") } }
    public var method: InputMethod { get { read("method", fallback: .carbon) } set { write(newValue, "method") } }
    public var side: ModifierSide { get { read("side", fallback: .rightOption) } set { write(newValue, "side") } }
    public var panels: [PanelRecord] { get { read("panels", fallback: []) } set { write(newValue, "panels") } }
    public var guided: Bool { get { defaults.bool(forKey: "guided") } set { defaults.set(newValue, forKey: "guided") } }
    public static func normalize(_ text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s.contains("://") ? s : "https://"+s), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }; return url
    }
}
#if DEBUG || TRIAL_DIAGNOSTICS
public struct Diagnostics {
    public var deltaMS: Double?; public var heldMS: Double = 0; public var release = "none"
    public var keyCode: UInt16 = 0; public var permission = false
    public var panels = 0; public var live = 0; public var rss: UInt64 = 0
    public init() {}
    public var text: String {
        let source = ["carbon", "flags poll", "event tap", "none"].contains(release) ? release : "none"
        return "press→release: \(deltaMS.map { String(format: "%.1f ms", $0) } ?? "—")\nrelease: \(source)\nheld: \(Int(heldMS)) ms\nmodifier keyCode: \(keyCode)\nlisten permission: \(permission)\npanels: \(panels) live: \(live) dormant: \(panels-live)\nprocess RSS: \(rss) bytes"
    }
}
#endif
