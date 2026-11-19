import AppKit

enum SlackLinks {
    static func desktopURL(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host?.lowercased(),
              host == "slack.com" || host.hasSuffix(".slack.com"), url.user == nil, url.password == nil else { return nil }
        let path = url.pathComponents.dropFirst().map { $0 }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var team = query.first { $0.name == "team" }?.value
        let channel: String
        var timestamp: String?
        if path.first == "archives", (2...3).contains(path.count) {
            channel = path[1]
            if path.count == 3 {
                guard path[2].range(of: "^p[0-9]{16}$", options: .regularExpression) != nil else { return nil }
                let digits = path[2].dropFirst()
                timestamp = String(digits.dropLast(6)) + "." + String(digits.suffix(6))
            }
        } else if path.first == "client", path.count == 3 {
            team = path[1]; channel = path[2]
        } else { return nil }
        guard channel.range(of: "^[CDG][A-Z0-9]+$", options: .regularExpression) != nil else { return nil }
        var parts = URLComponents()
        parts.scheme = "slack"; parts.host = "channel"
        var items = [URLQueryItem(name: "id", value: channel)]
        if let team, team.range(of: "^[TE][A-Z0-9]+$", options: .regularExpression) != nil { items.append(URLQueryItem(name: "team", value: team)) }
        if let timestamp { items.append(URLQueryItem(name: "message", value: timestamp)) }
        if let thread = query.first(where: { $0.name == "thread_ts" })?.value,
           thread.range(of: "^[0-9]+[.][0-9]{6}$", options: .regularExpression) != nil { items.append(URLQueryItem(name: "thread_ts", value: thread)) }
        parts.queryItems = items
        return parts.url
    }

    @discardableResult static func open(_ url: URL) -> Bool {
        if let destination = desktopURL(url), NSWorkspace.shared.urlForApplication(toOpen: destination) != nil,
           NSWorkspace.shared.open(destination) { return true }
        return NSWorkspace.shared.open(url)
    }
}
