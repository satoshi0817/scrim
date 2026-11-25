import Foundation
import CoreFoundation
import CoreGraphics

public enum OverlayState: Equatable { case hidden, peek, pinned
    public var ignoresMouse: Bool { VisibilityPlan(state: self).ignoresMouseEvents }
    public var needsKey: Bool { VisibilityPlan(state: self).makeKey }
}
/// A fresh plan is applied on every show, including repeated pinned shows.
public struct VisibilityPlan: Equatable {
    public let alpha: Double
    public let ignoresMouseEvents: Bool
    public let makeKey: Bool
    public let showPinnedPill: Bool
    public let showsPanelMenuButton: Bool
    public let usesOrderOut = false
    public let fadeDuration: TimeInterval
    public init(state: OverlayState, peekAllowsInteraction: Bool = true) {
        alpha = state == .hidden ? 0 : 1
        ignoresMouseEvents = state == .hidden || (state == .peek && !peekAllowsInteraction)
        makeKey = state == .pinned
        showPinnedPill = state == .pinned
        showsPanelMenuButton = state == .pinned
        fadeDuration = 0.25
    }
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
    public mutating func pin() { began = nil; closing = false; state = .pinned }
}
public enum ModifierSide: String, Codable, CaseIterable {
    case leftCommand, rightCommand, leftOption, rightOption, leftControl, rightControl, leftShift, rightShift
    public var mask: UInt64 { [0x08,0x10,0x20,0x40,0x01,0x2000,0x02,0x04][Self.allCases.firstIndex(of: self)!] }
    public var keyCode: UInt16 { [55,54,58,61,59,62,56,60][Self.allCases.firstIndex(of: self)!] }
    public static func from(keyCode: UInt16) -> Self? { allCases.first { $0.keyCode == keyCode } }
    public static func pressed(rawFlags: UInt64) -> Set<Self> { Set(allCases.filter { rawFlags & $0.mask != 0 }) }
}
public enum InputMethod: String, Codable, CaseIterable { case carbon, flagsPoll, eventTap }
/// Shared permission copy and display policy for guides, settings and previews.
public struct GuideContent: Equatable {
    public static func shortcutSentence(shortcut: Shortcut) -> String {
        "\(shortcut.displayString) を押している間だけ表示します。"
    }
    public static let permissionNoteText = "修飾キーだけで使う場合は、入力監視の許可が必要です。"
    public static let fallbackNoteText = "未許可時は押すたびに開閉します。"
    public static let permissionRequestTitle = "入力監視の許可をリクエスト"
    public static let permissionGrantedText = "入力監視：許可済み"
    public let showsPermissionNote: Bool
    public let permissionNote: String?
    public let permissionBlockText: String?
    public init(method: InputMethod) {
        showsPermissionNote = method != .carbon
        permissionNote = showsPermissionNote ? Self.permissionNoteText : nil
        permissionBlockText = permissionNote.map { method == .eventTap ? $0 + "\n" + Self.fallbackNoteText : $0 }
    }
}
public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public static let `default` = Shortcut(keyCode: 35, modifiers: 0x1000 | 0x0800)
    public init() { self = Self.default }
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let testCopy = Shortcut(keyCode: 80, modifiers: 0x1000 | 0x0800 | 0x0100)
    public var displayString: String {
        // Physical ANSI key names; no event characters or typed text are read.
        let keys: [UInt32: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
            25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            64: "F17", 76: "Enter", 79: "F18", 80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "PageUp",
            117: "ForwardDelete", 118: "F4", 119: "End", 120: "F2", 121: "PageDown", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let flags: [(UInt32, String)] = [(0x1000, "⌃"), (0x0800, "⌥"), (0x0100, "⌘"), (0x0200, "⇧")]
        let prefix = flags.filter { modifiers & $0.0 != 0 }.map { $0.1 }.joined()
        return prefix + (keys[keyCode] ?? "キー\(keyCode)")
    }
}
/// Contains only key configuration and system status, never personal content.
public enum HotkeyRegistrationStatus: Equatable {
    case success
    case carbonFailure(shortcut: Shortcut, status: Int32)
    case modifierUnavailable(side: ModifierSide)
    public init(carbonStatus: Int32, shortcut: Shortcut) {
        self = carbonStatus == 0 ? .success : .carbonFailure(shortcut: shortcut, status: carbonStatus)
    }
    public var message: String? {
        switch self {
        case .success: return nil
        case .carbonFailure:
            return RegistrationFeedback.message(self)
        case .modifierUnavailable(let side):
            let names = ["左 Command", "右 Command", "左 Option", "右 Option", "左 Control", "右 Control", "左 Shift", "右 Shift"]
            let name = names[ModifierSide.allCases.firstIndex(of: side)!]
            return "修飾キー \(name) のイベント監視を開始・継続できません。状態のポーリングで押すたびに開閉します。入力監視の許可を確認するか、上の欄で別のキーを押してください。"
        }
    }
}
/// Fractions of the full NSScreen.frame, using bottom-left screen-local coordinates.
public struct FractionalFrame: Codable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(frame: CGRect, screen: CGSize) {
        x = frame.minX / max(1, screen.width); y = frame.minY / max(1, screen.height)
        width = frame.width / max(1, screen.width); height = frame.height / max(1, screen.height)
    }
    public func restore(screen: CGSize) -> CGRect {
        Placement.constrain(CGRect(x: x*screen.width, y: y*screen.height, width: width*screen.width, height: height*screen.height), screen: screen, snapToGrid: false)
    }
}
/// Display-relative cells include gutters; panel edges stop before the next cell.
public struct PanelGrid {
    public let bounds: CGRect
    public let gap: CGFloat
    public let step: CGSize
    public init(screen: CGSize) {
        let margin = min(32, max(16, min(screen.width, screen.height)*0.02))
        gap = margin/2
        bounds = CGRect(x: margin, y: margin, width: max(1, screen.width-2*margin), height: max(1, screen.height-2*margin))
        step = CGSize(width: (bounds.width+gap)/CGFloat(Placement.gridColumns),
                      height: (bounds.height+gap)/CGFloat(Placement.gridRows))
    }
    public func frame(column: Int, row: Int, columns: Int, rows: Int) -> CGRect {
        CGRect(x: bounds.minX+CGFloat(column)*step.width, y: bounds.minY+CGFloat(row)*step.height,
               width: CGFloat(columns)*step.width-gap, height: CGFloat(rows)*step.height-gap)
    }
}
public enum Placement {
    public static let gridColumns = 12
    public static let gridRows = 8
    public static func gridStep(screen: CGSize) -> CGSize { PanelGrid(screen: screen).step }
    public static let snapThreshold: CGFloat = 10
    public static let visible: CGFloat = 40
    public static func constrain(_ rect: CGRect, screen: CGSize, others: [CGRect] = [], snapToGrid: Bool = true) -> CGRect {
        guard snapToGrid else {
            var r = rect; r.size.width = max(240, r.width); r.size.height = max(160, r.height)
            r.origin.x = min(max(r.minX, visible-r.width), max(0, screen.width-visible))
            r.origin.y = min(max(r.minY, visible-r.height), max(0, screen.height-visible))
            return r
        }
        let grid = PanelGrid(screen: screen), step = grid.step, gap = grid.gap
        let minWidth = ceil((240+gap)/step.width)*step.width-gap
        let minHeight = ceil((160+gap)/step.height)*step.height-gap
        var r = CGRect(x: grid.bounds.minX+((rect.minX-grid.bounds.minX)/step.width).rounded()*step.width,
                       y: grid.bounds.minY+((rect.minY-grid.bounds.minY)/step.height).rounded()*step.height,
                       width: min(grid.bounds.width, max(minWidth, ((rect.width+gap)/step.width).rounded()*step.width-gap)),
                       height: min(grid.bounds.height, max(minHeight, ((rect.height+gap)/step.height).rounded()*step.height-gap)))
        for other in others {
            for edge in [other.minX, other.maxX+gap] where abs(rect.minX-edge) <= snapThreshold { r.origin.x = edge }
            for edge in [other.maxX, other.minX-gap] where abs(rect.maxX-edge) <= snapThreshold { r.origin.x = edge-r.width }
            for edge in [other.minY, other.maxY+gap] where abs(rect.minY-edge) <= snapThreshold { r.origin.y = edge }
            for edge in [other.maxY, other.minY-gap] where abs(rect.maxY-edge) <= snapThreshold { r.origin.y = edge-r.height }
        }
        r.origin.x = min(max(r.minX, grid.bounds.minX), max(grid.bounds.minX, grid.bounds.maxX-r.width))
        r.origin.y = min(max(r.minY, grid.bounds.minY), max(grid.bounds.minY, grid.bounds.maxY-r.height))
        return r
    }
}
public struct PanelRecord: Codable, Identifiable {
    public var id: UUID; public var url: URL; public var placement: FractionalFrame
    public var webDisplayMode: WebDisplayMode?
    public init(id: UUID = UUID(), url: URL, placement: FractionalFrame, webDisplayMode: WebDisplayMode? = nil) {
        self.id = id; self.url = url; self.placement = placement; self.webDisplayMode = webDisplayMode
    }
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
/// Closes panel metadata only; the source URL is never modified.
public enum PanelActions {
    public static func close(_ id: UUID, records: inout [PanelRecord], pool: inout PanelPool) {
        pool.remove(id)
        records.removeAll { $0.id == id }
    }
}
public protocol SettingsStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func object(forKey key: String) -> Any?
    func setData(_ data: Data?, forKey key: String)
}
public extension SettingsStorage {
    func object(forKey key: String) -> Any? { data(forKey: key) }
}
extension UserDefaults: SettingsStorage {
    public func setData(_ data: Data?, forKey key: String) { set(data, forKey: key) }
}
public final class MemorySettingsStorage: SettingsStorage {
    private var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] }
    public func setData(_ data: Data?, forKey key: String) { values[key] = data }
}
public final class SettingsStore {
    private let storage: SettingsStorage
    public init(storage: SettingsStorage) { self.storage = storage }
    public convenience init(defaults: UserDefaults) { self.init(storage: defaults) }
    private func read<T: Decodable>(_ key: String, fallback: T) -> T { guard let data = storage.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }; return value }
    private func write<T: Encodable>(_ value: T, _ key: String) { storage.setData(try? JSONEncoder().encode(value), forKey: key) }
    public var gesture: GestureSettings { get { read("doublePress", fallback: GestureSettings()) } set { write(newValue, "doublePress") } }
    public var gesturePermissionDeferred: Bool { get { read("gesturePermissionDeferred", fallback: false) } set { write(newValue, "gesturePermissionDeferred") } }
    public var gesturePermissionAsked: Bool { get { read("gesturePermissionAsked", fallback: false) } set { write(newValue, "gesturePermissionAsked") } }
    public var shortcut: Shortcut { get { read("shortcut", fallback: Shortcut.default) } set { write(newValue, "shortcut") } }
    public var method: InputMethod { get { read("method", fallback: .carbon) } set { write(newValue, "method") } }
    public var side: ModifierSide { get { read("side", fallback: .rightOption) } set { write(newValue, "side") } }
    public var hideFromScreenCapture: Bool { get { read("hideFromScreenCapture", fallback: true) } set { write(newValue, "hideFromScreenCapture") } }
    public var weatherShowsHourly: Bool { get { read("weatherShowsHourly", fallback: true) } set { write(newValue, "weatherShowsHourly") } }
    public var webDisplayMode: WebDisplayMode { get { read("webDisplayMode", fallback: .desktop) } set { write(newValue, "webDisplayMode") } }
    public var notchMeetingsEnabled: Bool { get { read("notchMeetingsEnabled", fallback: true) } set { write(newValue, "notchMeetingsEnabled") } }
    public var notchLeadMinutes: Int { get { read("notchLeadMinutes", fallback: 10) } set { write(newValue, "notchLeadMinutes") } }
    public var notchLimitHours: Int { get { read("notchLimitHours", fallback: 3) } set { write(newValue, "notchLimitHours") } }
    public var notchOnlineOnly: Bool { get { read("notchOnlineOnly", fallback: false) } set { write(newValue, "notchOnlineOnly") } }
    public var appearanceMode: AppearanceMode { get { read("appearanceMode", fallback: .system) } set { write(newValue, "appearanceMode") } }
    public var agendaResetsScrollOnOpen: Bool { get { read("agendaResetsScrollOnOpen", fallback: true) } set { write(newValue, "agendaResetsScrollOnOpen") } }
    public var peekAllowsInteraction: Bool { get { read("peekAllowsInteraction", fallback: true) } set { write(newValue, "peekAllowsInteraction") } }
    public var calendarReturnsToToday: Bool { get { read("calendarReturnsToToday", fallback: true) } set { write(newValue, "calendarReturnsToToday") } }
    // NSEvent's device-independent Shift, Control, Option and Command bits.
    public var pageArrowModifiers: UInt {
        get { read("pageArrowModifiers", fallback: UInt(0x180000)) }
        set { if newValue != 0 && newValue & ~UInt(0x1e0000) == 0 { write(newValue, "pageArrowModifiers") } }
    }
    public var pageCount: Int { max(1, read("canvasPageCount", fallback: 1)) }
    public var currentPage: Int {
        get { min(pageCount - 1, max(0, read("canvasPage", fallback: 0))) }
        set { write(min(pageCount - 1, max(0, newValue)), "canvasPage") }
    }
    public func appendPage() -> Int {
        let index = pageCount
        // Always initialize this slot, including an index reused after a page reset.
        write([PanelRecord](), pageKey("panels", page: index))
        write([String: DisplayLayout](), pageKey("layoutsByDisplay", page: index))
        storage.setData(nil, forKey: pageKey("sharedLayoutReferenceSize", page: index))
        write(index + 1, "canvasPageCount")
        return index
    }
    /// Returns original indices in their new order so in-memory sessions follow the same move.
    public func movePage(_ source: Int, to destination: Int) -> [Int] {
        var order = Array(0..<pageCount)
        guard source != destination, order.indices.contains(source), order.indices.contains(destination) else { return order }
        let selected = currentPage
        order.insert(order.remove(at: source), at: destination)
        for key in ["panels", "layoutsByDisplay", "sharedLayoutReferenceSize"] {
            let values = order.map { storage.data(forKey: pageKey(key, page: $0)) }
            for (index, value) in values.enumerated() where index != order[index] {
                storage.setData(value, forKey: pageKey(key, page: index))
            }
        }
        currentPage = order.firstIndex(of: selected)!
        return order
    }

    public func removePage(_ index: Int) {
        let count = pageCount, selected = currentPage
        guard count > 1, (0..<count).contains(index) else { return }
        for page in index..<count {
            for key in ["panels", "layoutsByDisplay", "sharedLayoutReferenceSize"] {
                let next = page + 1 < count ? storage.data(forKey: pageKey(key, page: page + 1)) : nil
                storage.setData(next, forKey: pageKey(key, page: page))
            }
        }
        write(count - 1, "canvasPageCount")
        currentPage = selected > index ? selected - 1 : min(selected, count - 2)
    }

    private func pageKey(_ key: String, page: Int? = nil) -> String {
        let index = page ?? currentPage
        return index == 0 ? key : "page.\(index).\(key)"
    }
    public func panelsAcrossPages(display: String) -> [PanelRecord] {
        let shared = sameLayoutOnAllDisplays
        return (0..<pageCount).flatMap { index -> [PanelRecord] in
            if !shared {
                let layouts: [String: DisplayLayout] = read(pageKey("layoutsByDisplay", page: index), fallback: [:])
                if let layout = layouts[display] { return layout.panels }
            }
            return read(pageKey("panels", page: index), fallback: [])
        }
    }

    public var panels: [PanelRecord] { get { read(pageKey("panels"), fallback: []) } set { write(newValue, pageKey("panels")) } }
    public var sameLayoutOnAllDisplays: Bool { get { read("sameLayoutOnAllDisplays", fallback: true) } set { write(newValue, "sameLayoutOnAllDisplays") } }
    public var showsOverlayControls: Bool { get { read("showsOverlayControls", fallback: false) } set { write(newValue, "showsOverlayControls") } }
    public var sharedLayoutReferenceSize: CGSize? {
        get { read(pageKey("sharedLayoutReferenceSize"), fallback: Optional<LayoutSize>.none)?.size }
        set { write(newValue.map { LayoutSize($0) }, pageKey("sharedLayoutReferenceSize")) }
    }
    public var layoutsByDisplay: [String: DisplayLayout] { get { read(pageKey("layoutsByDisplay"), fallback: [:]) } set { write(newValue, pageKey("layoutsByDisplay")) } }
    public var guided: Bool { get { Self.isGuidedTrue(storage.object(forKey: "guided")) } set { write(newValue, "guided") } }
    private static func isGuidedTrue(_ value: Any?) -> Bool {
        if let data = value as? Data {
            if let bool = try? JSONDecoder().decode(Bool.self, from: data) { return bool }
            if let string = try? JSONDecoder().decode(String.self, from: data) { return string == "true" }
            return String(data: data, encoding: .utf8) == "true"
        }
        if let string = value as? String { return string == "true" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
        }
        return false
    }
    public func beginFirstRunGuidance() -> Bool {
        guard !guided else { return false }
        guided = true
        return true
    }
    public func finishFirstRunGuidance() { guided = true }
    public func dockVisible(isTrial: Bool) -> Bool { read("dockVisible", fallback: isTrial) }
    public var dockVisible: Bool {
        get { dockVisible(isTrial: ScrimBuild.isTrial) }
        set { write(newValue, "dockVisible") }
    }
    public static func normalize(_ text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s.contains("://") ? s : "https://"+s), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }; return url
    }
}
#if DEBUG || TRIAL_DIAGNOSTICS
public struct Diagnostics {
    public var deltaMS: Double?; public var heldMS: Double = 0; public var release = "none"
    public var keyCode: UInt16?; public var permission = false
    public var panels = 0; public var live = 0; public var rss: UInt64 = 0
    public init() {}
    public var text: String {
        let source = ["carbon", "flags poll", "event tap", "none"].contains(release) ? release : "none"
        let observed = keyCode.flatMap { code in ModifierSide.from(keyCode: code).map { "\(code) (\($0.rawValue))" } } ?? "none"
        return "press→release: \(deltaMS.map { String(format: "%.1f ms", $0) } ?? "—")\nrelease: \(source)\nheld: \(Int(heldMS)) ms\nmodifier keyCode: \(observed)\nlisten permission: \(permission)\npanels: \(panels) live: \(live) dormant: \(panels-live)\nprocess RSS: \(rss) bytes"
    }
}
#endif

public enum WebDisplayMode: String, Codable, CaseIterable { case desktop, mobile }

public enum AppearanceMode: String, Codable, CaseIterable { case system, light, dark }
