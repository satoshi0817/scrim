import AppKit
import WebKit

final class PanelWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum PanelPointerEvents {
    /// Remove the held invocation key only from pointer events delivered to Scrim.
    /// The global listen-only monitor still receives the physical key release.
    static func withoutCommand(_ event: NSEvent) -> NSEvent {
        guard event.modifierFlags.contains(.command) else { return event }
        let flags = event.modifierFlags.subtracting(.command)
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return NSEvent.mouseEvent(with: event.type, location: event.locationInWindow, modifierFlags: flags,
                                      timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                      eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure) ?? event
        case .scrollWheel:
            guard let copy = event.cgEvent?.copy() else { return event }
            copy.flags.remove(.maskCommand)
            guard let normalized = NSEvent(cgEvent: copy), normalized.windowNumber == event.windowNumber else { return event }
            return normalized
        default: return event
        }
    }
}
