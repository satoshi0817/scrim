import AppKit

/// Layout only: each native button supplies its own glass surface.
final class OverlayControls: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("パネルのレイアウト")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {}
}
