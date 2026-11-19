import AppKit
import ScrimCore

final class GesturePermissionView: NSView {
    private var primaryButton: NSButton?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.defaultButtonCell = primaryButton?.cell as? NSButtonCell
    }
    init(state: GesturePermissionState, unavailable: Bool = false, allow: (() -> Void)? = nil, later: (() -> Void)? = nil, openSettings: (() -> Void)? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: GestureSettingsPresentation.permissionCardWidth, height: GestureSettingsPresentation.permissionCardHeight))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        func text(_ value: String, y: CGFloat, height: CGFloat, size: CGFloat = 14) {
            let v = NSTextField(wrappingLabelWithString: value)
            v.font = .systemFont(ofSize: size); v.textColor = .labelColor
            v.maximumNumberOfLines = 0; v.lineBreakMode = .byWordWrapping
            v.frame = NSRect(x: 24, y: y, width: GestureSettingsPresentation.bodyWidth, height: height); addSubview(v)
        }
        text(GestureCopy.heading, y: 230, height: 66, size: 20)
        text(GestureCopy.body, y: 124, height: GestureSettingsPresentation.bodyHeight)
        if state == .granted { text(GestureCopy.granted, y: 50, height: 40, size: 20) }
        else {
            if state == .denied { text(unavailable ? "入力監視を開始できません。⌃⌥P で使えます。" : GestureCopy.denied, y: 80, height: 32) }
            let primary = ActionButton(state == .denied ? "システム設定を開く" : GestureCopy.allow) { if state == .denied { openSettings?() } else { allow?() } }
            primaryButton = primary
            primary.keyEquivalent = "\r"; primary.bezelColor = .controlAccentColor
            primary.frame = NSRect(x: 24, y: 28, width: 230, height: 32); addSubview(primary)
            let secondary = ActionButton(GestureCopy.later) { later?() }
            secondary.keyEquivalent = ""; secondary.bezelColor = nil
            secondary.frame = NSRect(x: 270, y: 28, width: 286, height: 32); addSubview(secondary)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}
final class GestureSettingsView: NSView {
    private let store: SettingsStore
    var changed: (() -> Void)?
    var permissionRequested: (() -> Void)?
    var gestureEnabled: (() -> Void)?
    var layoutChanged: (() -> Void)?
    var permissionGranted = false { didSet { if oldValue != permissionGranted { rebuild() } } }
    var expanded = false { didSet { rebuild(); layoutChanged?() } }
    init(store: SettingsStore) { self.store = store; super.init(frame: NSRect(x: 0, y: 0, width: 560, height: 300)); rebuild() }
    required init?(coder: NSCoder) { fatalError() }
    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        let height = expanded ? GestureSettingsPresentation.expandedHeight : GestureSettingsPresentation.collapsedHeight
        frame.size.height = height
        func text(_ value: String, _ y: CGFloat, _ size: CGFloat = 13) {
            let v = label(value, size: size); v.textColor = .secondaryLabelColor
            v.frame = NSRect(x: 0, y: y, width: 560, height: 24); addSubview(v)
        }
        let enabled = NSButton(checkboxWithTitle: GestureSettingsPresentation.checkboxTitle(fn: store.gesture.useFn), target: self, action: #selector(toggleEnabled))
        enabled.state = store.gesture.enabled ? .on : .off; enabled.frame = NSRect(x: 0, y: height-26, width: 300, height: 24); addSubview(enabled)
        if GestureSettingsPresentation.showsWaiting(granted: permissionGranted) {
            text(GestureSettingsPresentation.waiting, height-58)
            let permission = ActionButton(GestureSettingsPresentation.permissionButton) { [weak self] in self?.permissionRequested?() }
            permission.frame = NSRect(x: 310, y: height-58, width: 250, height: 26); addSubview(permission)
        }
        let side = NSPopUpButton(frame: NSRect(x: 0, y: height-90, width: 250, height: 28))
        side.addItems(withTitles: CommandChoice.allCases.map(\.rawValue)); side.selectItem(at: CommandChoice.allCases.firstIndex(of: store.gesture.command)!)
        side.isEnabled = GestureSettingsPresentation.commandPickerEnabled(fn: store.gesture.useFn)
        side.target = self; side.action = #selector(sideChanged); addSubview(side)
        let detail = ActionButton(expanded ? "▾ 詳細" : "▸ 詳細") { [weak self] in guard let self else { return }; self.expanded.toggle() }
        detail.frame = NSRect(x: 0, y: height-124, width: 100, height: 26); addSubview(detail)
        guard expanded else {
            text("2回目を押している間は、元のアプリのまま閲覧できます。", 140)
            text("2回目を短く離すと固定、長く押して離すと閉じます。", 108)
            text("許可がない場合も \(store.shortcut.displayString) で使えます。", 76)
            return
        }
        for (i, pair) in [("1回目の最長（秒）", store.gesture.firstTapMax), ("2回目までの間隔（秒）", store.gesture.gapMax), ("固定する境界（秒）", store.gesture.pinThreshold)].enumerated() {
            let y = CGFloat(height - 154 - Double(i) * 30)
            text(pair.0, y)
            let field = NSTextField(string: String(format: "%.2f", pair.1)); field.frame = NSRect(x: 260, y: y, width: 90, height: 24); field.tag = i; field.target = self; field.action = #selector(timingChanged); addSubview(field)
        }
        let fn = NSButton(checkboxWithTitle: "上級者向け：fn / 🌐 を使う", target: self, action: #selector(fnChanged)); fn.state = store.gesture.useFn ? .on : .off; fn.frame = NSRect(x: 0, y: height-246, width: 330, height: 24); addSubview(fn)
        if store.gesture.useFn {
            // All caution views share the same regular font and semantic secondary color.
            // VS15 requests a monochrome text globe rather than color emoji.
            let font = NSFont.systemFont(ofSize: 12, weight: .regular)
            var top = GestureSettingsPresentation.cautionTop
            for caution in GestureCopy.cautions {
                let text = "• " + caution.replacingOccurrences(of: "🌐", with: "🌐\u{FE0E}")
                let v = FnCautionLabel(text: text, font: font)
                let height = max(20, ceil(v.textHeight(width: 560)))
                v.frame = NSRect(x: 0, y: top-height, width: 560, height: height)
                addSubview(v)
                top -= height + GestureSettingsPresentation.cautionGap
            }
            let keyboard = ActionButton("キーボード設定を開く") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
            keyboard.frame = NSRect(x: 0, y: GestureSettingsPresentation.keyboardButtonY, width: 210, height: 28); addSubview(keyboard)
        }
    }
    @objc private func toggleEnabled(_ sender: NSButton) { store.gesture.enabled = sender.state == .on; changed?(); if store.gesture.enabled { gestureEnabled?() } }
    @objc private func sideChanged(_ sender: NSPopUpButton) { store.gesture.command = CommandChoice.allCases[sender.indexOfSelectedItem]; changed?() }
    @objc private func fnChanged(_ sender: NSButton) { store.gesture.useFn = sender.state == .on; changed?(); rebuild(); if !store.gesture.useFn && store.gesture.enabled { gestureEnabled?() } }
    @objc private func timingChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue), value.isFinite, value > 0, value <= 2 else { rebuild(); return }
        switch sender.tag { case 0: store.gesture.firstTapMax = value; case 1: store.gesture.gapMax = value; default: store.gesture.pinThreshold = value }
        changed?()
    }
}

/// Offscreen window-chrome fixture; never orders a window or installs an input listener.
final class GesturePermissionPreviewView: NSView {
    init(state: GesturePermissionState) {
        let card = GesturePermissionView(state: state)
        super.init(frame: NSRect(x: 0, y: 0, width: card.frame.width, height: card.frame.height + 32))
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 10; layer?.borderWidth = 1; layer?.borderColor = NSColor.separatorColor.cgColor
        let chrome = NSView(frame: NSRect(x: 0, y: card.frame.height, width: frame.width, height: 32))
        chrome.wantsLayer = true; chrome.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let title = NSTextField(labelWithString: "Scrim"); title.textColor = .labelColor; title.alignment = .center
        title.font = .systemFont(ofSize: 13, weight: .semibold); title.frame = NSRect(x: 20, y: 6, width: frame.width-40, height: 20)
        chrome.addSubview(title); addSubview(chrome); addSubview(card)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Draw all caution runs identically, bypassing NSTextField's emoji-specific
/// semantic-label treatment. The semantic system color is resolved at draw time.
private final class FnCautionLabel: NSView {
    let text: String
    let font: NSFont
    override var isFlipped: Bool { true }
    init(text: String, font: NSFont) {
        self.text = text; self.font = font
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var styledText: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 20; style.maximumLineHeight = 20
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style
        ])
    }
    func textHeight(width: CGFloat) -> CGFloat {
        styledText.boundingRect(with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    }
    override func draw(_ dirtyRect: NSRect) {
        styledText.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
