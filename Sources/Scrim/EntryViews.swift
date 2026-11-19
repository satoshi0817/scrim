import AppKit
import ScrimCore
import ScrimAssets

/// Offscreen review fixture, not a system menu or evidence of real menu-bar visibility.
final class EntryMenuPreviewView: NSView {
    init(state: EntryState, showMenu: Bool, gestureStatus: String? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 660, height: 430))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; layer?.cornerRadius = 12
        let caption = NSTextField(labelWithString: "プレビュー — 実際のメニューバー表示の証拠ではありません")
        caption.font = .systemFont(ofSize: 13); caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 22, y: 380, width: 620, height: 30); addSubview(caption)
        let icon = NSImageView(frame: NSRect(x: 34, y: 334, width: 18, height: 18))
        icon.image = StatusIcon.image(warning: state.showsWarning); icon.contentTintColor = .labelColor; addSubview(icon)
        let symbol = NSTextField(labelWithString: "Scrim · \(StatusIcon.resourceName(warning: state.showsWarning))")
        symbol.frame = NSRect(x: 72, y: 330, width: 550, height: 28); addSubview(symbol)
        guard showMenu else { return }
        let rows = (gestureStatus.map { [$0] } ?? []) + [state.openTitle, state.menuTitles[1], "────────────", state.menuTitles[2]]
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
