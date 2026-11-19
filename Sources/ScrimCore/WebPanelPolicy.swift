import Foundation

public enum WebPanelPolicy {
    /// Standard Notion "Copy link to view" URLs identify the selected view with v.
    public static func notionViewURL(_ input: String) -> URL? {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["https", "notion"].contains(scheme),
              let host = parts.host?.lowercased(), parts.user == nil, parts.password == nil,
              ["notion.so", "notion.site", "notion.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              host != "calendar.notion.com", !parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty,
              let view = parts.queryItems?.first(where: { $0.name == "v" })?.value,
              view.range(of: #"^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$"#, options: .regularExpression) != nil else { return nil }
        parts.scheme = "https"
        parts.queryItems = [URLQueryItem(name: "v", value: view)]
        return parts.url
    }
    public static func isNotionCalendar(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "calendar.notion.com"
    }
    public static func canReturnToToday(_ url: URL) -> Bool {
        isNotionCalendar(url) && !url.path.hasPrefix("/auth") && !url.path.hasPrefix("/login")
    }
    /// Login callbacks and dated routes are transient, not panel launch addresses.
    public static func launchURL(_ url: URL) -> URL {
        isNotionCalendar(url) ? URL(string: "https://calendar.notion.com/")! : url
    }
    public static func savedURL(_ navigated: URL, previous: URL) -> URL {
        if notionViewURL(previous.absoluteString) != nil { return previous }
        if isNotionCalendar(previous) { return launchURL(previous) }
        let parts = URLComponents(url: navigated, resolvingAgainstBaseURL: false)
        let transient = ["code", "access_token", "id_token", "refresh_token"]
        if parts?.queryItems?.contains(where: { transient.contains($0.name.lowercased()) }) == true { return launchURL(previous) }
        return launchURL(navigated)
    }
}


public extension SettingsStore {
    func normalizeWebLaunchURLs() {
        var shared = panels
        let sharedChanged = shared.contains { WebPanelPolicy.launchURL($0.url) != $0.url }
        if sharedChanged {
            for index in shared.indices { shared[index].url = WebPanelPolicy.launchURL(shared[index].url) }
            panels = shared
        }
        var layouts = layoutsByDisplay
        var changed = false
        for key in Array(layouts.keys) {
            guard var layout = layouts[key] else { continue }
            for index in layout.panels.indices {
                let clean = WebPanelPolicy.launchURL(layout.panels[index].url)
                if clean != layout.panels[index].url { layout.panels[index].url = clean; changed = true }
            }
            layouts[key] = layout
        }
        if changed { layoutsByDisplay = layouts }
    }
}
