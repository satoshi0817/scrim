import AppKit

/// The centered menu pill on a hovered panel in edit mode. The mouse passes through it: the panel itself
/// turns a click anywhere into the menu and a drag into a move. It stays in the accessibility tree
/// (transparent rather than hidden) as the panel's menu button.
final class PanelEditHint: NSView {
    var press: (() -> Void)?
    private let icon = NSImageView()
    private let text = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 1
        icon.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        icon.contentTintColor = .white
        text.font = .systemFont(ofSize: 13, weight: .semibold)
        text.textColor = .white
        stack.orientation = .horizontal; stack.spacing = 7; stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 16)
        stack.addArrangedSubview(icon); stack.addArrangedSubview(text)
        addSubview(stack)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("パネルのメニュー")
        text.stringValue = "クリックでメニュー · ドラッグで移動"
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        let size = stack.fittingSize
        return NSSize(width: ceil(size.width), height: 36)
    }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        stack.frame = bounds
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}
