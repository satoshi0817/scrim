import AppKit

/// Read-only document surface; selection, copy and scrolling stay native.
final class NativeTextPanel: NSScrollView {
    init(text: String) {
        super.init(frame: .zero)
        hasVerticalScroller = true; drawsBackground = true; backgroundColor = .textBackgroundColor
        let view = NSTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textColor = .textColor; view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 20, height: 20)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = .width; view.textContainer?.widthTracksTextView = true
        view.string = text; documentView = view
    }
    required init?(coder: NSCoder) { fatalError() }
}
