import Foundation

public enum EventExclusion {
    private static let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive]
    public static func normalized(_ keywords: [String]) -> [String] {
        var seen: Set<String> = []
        return keywords.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: options, locale: Locale(identifier: "en_US_POSIX"))
            return seen.insert(key).inserted ? trimmed : nil
        }
    }
    public static func matches(title: String, keywords: [String]) -> Bool {
        keywords.contains { value in
            let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !keyword.isEmpty && title.range(of: keyword, options: options, locale: Locale(identifier: "en_US_POSIX")) != nil
        }
    }
}
