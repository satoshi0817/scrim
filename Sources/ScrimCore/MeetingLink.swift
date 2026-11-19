import Foundation

public enum MeetingLink {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    public static func find(in values: [String?]) -> URL? {
        guard let detector else { return nil }
        for value in values.compactMap({ $0 }) {
            let text = value.replacingOccurrences(of: "&amp;", with: "&")
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in detector.matches(in: text, range: range) {
                guard let candidate = match.url, ["http", "https"].contains(candidate.scheme?.lowercased() ?? ""),
                      var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else { continue }
                components.scheme = "https"
                guard let url = components.url, service(for: url) != nil else { continue }
                return url
            }
        }
        return nil
    }
    public static func service(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        if host == "meet.google.com", url.path != "", url.path != "/" { return "Google Meet" }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoom.com" || host.hasSuffix(".zoom.com") {
            if ["/j/", "/my/", "/wc/", "/s/"].contains(where: { url.path.hasPrefix($0) }) { return "Zoom" }
        }
        return nil
    }
}
