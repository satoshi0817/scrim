import AppKit
import ChiraCore

enum StatusIcon {
    static var symbolName: String {
        EntryState.symbolCandidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: "Chira") != nil } ?? "drawn-window"
    }
    static func image(warning: Bool) -> NSImage {
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Chira")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            if let symbol { symbol.draw(in: rect.insetBy(dx: 1, dy: 1)) }
            else { NSColor.black.setStroke(); NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 3), xRadius: 2, yRadius: 2).stroke() }
            if warning {
                let badge = NSRect(x: 11, y: 0, width: 7, height: 7)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .copy
                NSColor.clear.setFill(); NSBezierPath(ovalIn: badge.insetBy(dx: -0.5, dy: -0.5)).fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.black.setStroke(); NSBezierPath(ovalIn: badge).stroke()
                let mark = NSBezierPath(); mark.move(to: NSPoint(x: 14.5, y: 2.7)); mark.line(to: NSPoint(x: 14.5, y: 5.5)); mark.lineWidth = 1; mark.stroke()
                NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 14, y: 1.1, width: 1, height: 1)).fill()
            }
            return true
        }
        image.isTemplate = true; return image
    }
}

/// Offscreen review fixture, not a system menu or evidence of real menu-bar visibility.
final class EntryMenuPreviewView: NSView {
    init(state: EntryState, showMenu: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 660, height: 430))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; layer?.cornerRadius = 12
        let caption = NSTextField(labelWithString: "プレビュー — 実際のメニューバー表示の証拠ではありません")
        caption.font = .systemFont(ofSize: 13); caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 22, y: 380, width: 620, height: 30); addSubview(caption)
        let icon = NSImageView(frame: NSRect(x: 34, y: 334, width: 18, height: 18))
        icon.image = StatusIcon.image(warning: state.showsWarning); icon.contentTintColor = .labelColor; addSubview(icon)
        let symbol = NSTextField(labelWithString: "Chira · \(StatusIcon.symbolName)")
        symbol.frame = NSRect(x: 72, y: 330, width: 550, height: 28); addSubview(symbol)
        guard showMenu else { return }
        let rows = [state.openTitle, state.menuTitles[1], "────────────", state.menuTitles[2]]
        for (index, title) in rows.enumerated() {
            let row = NSTextField(labelWithString: title); row.font = .menuFont(ofSize: 14)
            row.frame = NSRect(x: 30, y: 280-CGFloat(index)*38, width: 600, height: 30); addSubview(row)
        }
        if let failure = state.failureMessage {
            let text = NSTextField(wrappingLabelWithString: failure); text.textColor = .systemOrange
            text.frame = NSRect(x: 30, y: 28, width: 600, height: 94); addSubview(text)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}
