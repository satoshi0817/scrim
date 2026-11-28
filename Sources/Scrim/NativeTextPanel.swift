import AppKit
import Combine

class PanelTextView: NSTextView {
    var openWebLink: (URL) -> Void = { DefaultBrowser.open($0) }

    override func clicked(onLink link: Any, at charIndex: Int) {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url, DefaultBrowser.supports(url) {
            openWebLink(url)
        } else {
            super.clicked(onLink: link, at: charIndex)
        }
    }
}

/// Read-only document surface; selection, copy and scrolling stay native.
final class NativeTextPanel: NSScrollView {
    private var themeObservation: AnyCancellable?

    init(content: NSAttributedString, openWebLink: @escaping (URL) -> Void) {
        super.init(frame: .zero)
        hasVerticalScroller = true; drawsBackground = true
        let view = PanelTextView(frame: .zero)
        view.openWebLink = openWebLink
        view.isEditable = false; view.isSelectable = true
        view.usesAdaptiveColorMappingForDarkAppearance = true
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textColor = .textColor; view.drawsBackground = false
        view.textContainerInset = NSSize(width: 20, height: 20)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = .width; view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(content); documentView = view
        themeObservation = ScrimTheme.shared.$settings.sink { [weak self, weak view] _ in
            let accent = ScrimTheme.shared.accent
            self?.backgroundColor = accent.nativeBackground
            view?.linkTextAttributes = [.foregroundColor: accent.nativeInk, .underlineStyle: NSUnderlineStyle.single.rawValue]
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}
