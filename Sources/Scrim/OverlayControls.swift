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

/// Numbered page selector in layout editing. A click opens its menu; a drag moves the page.
final class EditablePageDot: NSButton, NSDraggingSource {
    private static let pageType = NSPasteboard.PasteboardType("com.satoshi0817.Scrim.canvas")
    let page: Int
    var move: ((Int, Int) -> Void)?
    var openMenu: ((EditablePageDot) -> Void)?

    init(page: Int, selected: Bool) {
        self.page = page
        super.init(frame: .zero)
        title = String(page + 1)
        isBordered = false
        font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        contentTintColor = selected ? .black : .white
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = selected ? NSColor.white.cgColor : NSColor.clear.cgColor
        target = self
        action = #selector(showActions)
        registerForDraggedTypes([Self.pageType])
        setAccessibilityLabel("ページ " + title + (selected ? "、表示中" : ""))
        toolTip = "クリックでページ操作、左右にドラッグして並べ替え"
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func showActions() { openMenu?(self) }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { performClick(nil) }
                return
            }
            let p = next.locationInWindow, origin = event.locationInWindow
            guard hypot(p.x-origin.x, p.y-origin.y) >= 4 else { continue }
            let item = NSPasteboardItem()
            item.setString(String(page), forType: Self.pageType)
            let drag = NSDraggingItem(pasteboardWriter: item)
            let image = NSImage(size: bounds.size, flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
                let text = NSAttributedString(string: self.title, attributes: [.foregroundColor: NSColor.white, .font: self.font!])
                text.draw(at: NSPoint(x: rect.midX-text.size().width/2, y: rect.midY-text.size().height/2))
                return true
            }
            drag.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [drag], event: next, source: self)
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let source = sender.draggingSource as? EditablePageDot, source !== self, source.superview === superview else { return [] }
        layer?.borderWidth = 2
        layer?.borderColor = ScrimTheme.shared.accent.nativeInk.cgColor
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.borderWidth = 0 }
    override func draggingEnded(_ sender: NSDraggingInfo) { layer?.borderWidth = 0 }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        guard let source = sender.draggingSource as? EditablePageDot, source !== self, source.superview === superview else { return false }
        move?(source.page, page)
        return true
    }
}
