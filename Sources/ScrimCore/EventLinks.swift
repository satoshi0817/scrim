import Foundation

public struct EventLink: Identifiable, Equatable {
    public let url: URL
    public let title: String
    public var id: String { url.absoluteString }
    public init(url: URL, title: String? = nil) { self.url = url; self.title = title ?? Self.serviceName(url) }
    public var meetingService: String? { MeetingLink.service(for: url) }
    public var host: String { url.host?.lowercased() ?? "" }
    public var isNotion: Bool { Self.domain(host, "notion.so") || Self.domain(host, "notion.site") || Self.domain(host, "notion.com") }
    public var symbol: String {
        if meetingService != nil { return "video.fill" }
        if isNotion { return host == "calendar.notion.com" ? "calendar" : "doc.text" }
        if Self.domain(host, "github.com") { return "chevron.left.forwardslash.chevron.right" }
        if Self.domain(host, "slack.com") { return "number" }
        if Self.domain(host, "figma.com") { return "square.stack.3d.up" }
        if Self.domain(host, "youtube.com") || host == "youtu.be" { return "play.rectangle.fill" }
        if host == "docs.google.com" {
            if url.path.hasPrefix("/spreadsheets/") { return "tablecells" }
            if url.path.hasPrefix("/presentation/") { return "rectangle.on.rectangle" }
            return "doc.text"
        }
        if host == "drive.google.com" { return "folder" }
        if Self.domain(host, "linear.app") { return "checklist" }
        if Self.domain(host, "atlassian.net") { return "doc.richtext" }
        return "link"
    }
    private static func domain(_ host: String, _ base: String) -> Bool { host == base || host.hasSuffix("." + base) }
    private static func serviceName(_ url: URL) -> String {
        if let meeting = MeetingLink.service(for: url) { return meeting }
        let host = url.host?.lowercased() ?? "リンク"
        if host == "calendar.notion.com" { return "Notion Calendar" }
        if domain(host, "notion.so") || domain(host, "notion.site") || domain(host, "notion.com") { return "Notion" }
        if domain(host, "github.com") { return "GitHub" }
        if domain(host, "slack.com") { return "Slack" }
        if domain(host, "figma.com") { return "Figma" }
        if domain(host, "youtube.com") || host == "youtu.be" { return "YouTube" }
        if host == "docs.google.com" {
            if url.path.hasPrefix("/spreadsheets/") { return "Google Sheets" }
            if url.path.hasPrefix("/presentation/") { return "Google Slides" }
            return "Google Docs"
        }
        if host == "drive.google.com" { return "Google Drive" }
        if domain(host, "linear.app") { return "Linear" }
        if domain(host, "atlassian.net") { return "Atlassian" }
        return host
    }
}

public enum EventLinks {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let anchors = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#)
    public static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
    }
    public static func extract(in values: [String?]) -> [EventLink] {
        guard let detector else { return [] }
        var seen: Set<String> = [], result: [EventLink] = []
        for raw in values.compactMap({ $0 }) {
            let text = decode(raw)
            var titles: [String: String] = [:]
            if let anchors {
                let ns = text as NSString
                for anchor in anchors.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let destination = ns.substring(with: anchor.range(at: 1))
                    let label = plainText(ns.substring(with: anchor.range(at: 2)))
                    if !label.isEmpty { titles[destination] = label }
                }
            }
            for match in detector.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
                guard var url = match.url, isWebURL(url) else { continue }
                if url.scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    parts.scheme = "https"
                    if let secure = parts.url, MeetingLink.service(for: secure) != nil { url = secure }
                }
                guard seen.insert(url.absoluteString).inserted else { continue }
                result.append(EventLink(url: url, title: titles[url.absoluteString]))
            }
        }
        return result
    }
    /// Render calendar notes as inert text; do not load HTML, images, or favicons.
    public static func notes(_ value: String?) -> String? {
        guard let value else { return nil }
        var text = plainText(value)
        if let detector {
            let ns = text as NSString
            for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let url = match.url, isWebURL(url), let range = Range(match.range, in: text) { text.removeSubrange(range) }
            }
        }
        text = text.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private static func plainText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div|li|h[1-6])\s*>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
        text = decode(text).replacingOccurrences(of: #"\n[ \t]*\n(?:[ \t]*\n)+"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}
