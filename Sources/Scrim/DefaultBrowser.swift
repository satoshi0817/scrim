import AppKit

@MainActor
enum DefaultBrowser {
    static func supports(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "https" || scheme == "http"
    }

    static func open(_ url: URL, onSuccess: (() -> Void)? = nil) {
        let workspace = NSWorkspace.shared
        // Resolve the browser by scheme so a site's native app cannot claim the destination.
        guard supports(url), let scheme = url.scheme?.lowercased(),
              let schemeURL = URL(string: scheme + ":"),
              let browser = workspace.urlForApplication(toOpen: schemeURL) else {
            NSSound.beep()
            return
        }
        Task {
            do {
                _ = try await workspace.open([url], withApplicationAt: browser, configuration: .init())
                onSuccess?()
            } catch {
                NSSound.beep()
            }
        }
    }
}
