import AppKit

/// Shared by the app, offscreen reviews and resource tests. No application is launched.
public enum StatusIcon {
    public static var resourceBundle: Bundle { .module }
    public static func resourceName(warning: Bool) -> String {
        warning ? "MenuBarWarningTemplate" : "MenuBarTemplate"
    }
    public static func resourceURL(name: String, extension ext: String, appBundle: Bundle = .main) -> URL? {
        appBundle.url(forResource: name, withExtension: ext)
            ?? resourceBundle.url(forResource: name, withExtension: ext)
    }
    public static func image(warning: Bool, appBundle: Bundle = .main) -> NSImage {
        let name = resourceName(warning: warning)
        guard let url = resourceURL(name: name, extension: "pdf", appBundle: appBundle),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Sheerpane template: \(name).pdf")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Sheerpane"
        return image
    }
}
