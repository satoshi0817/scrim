import AppKit
import ChiraCore

/// No window is ordered and no web view or hotkey is created in this path.
func renderPreviews(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let states = ["empty", "peek", "pinned", "dormant", "menu", "settings", "hotkey-error",
                  "guide-no-permission", "guide-permission", "first-panel"]
    for state in states {
        let root = Backdrop(frame: NSRect(x: 0, y: 0, width: 1800, height: 1169))
        let host = NSWindow(contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
        host.contentView = root; host.isReleasedWhenClosed = false
        if state == "guide-no-permission" || state == "guide-permission" {
            let store = SettingsStore(storage: MemorySettingsStorage())
            store.method = state == "guide-permission" ? .eventTap : .carbon
            let guide = FirstRunGuideView(shortcut: store.shortcut, method: store.method)
            guide.frame.origin = NSPoint(x: 590, y: 384); root.addSubview(guide)
        } else if state == "settings" || state == "hotkey-error" {
            let settings = SettingsController(store: SettingsStore(storage: MemorySettingsStorage()), permissionState: { false })
            if state == "hotkey-error" { settings.registrationStatus = .carbonFailure(shortcut: Shortcut(), status: -9878) }
            if let content = settings.window.contentView { content.removeFromSuperview(); content.frame.origin = NSPoint(x: 590, y: 180); root.addSubview(content) }
        } else if state == "empty" {
            let button = ActionButton("最初のパネルを追加", action: {}); button.frame = NSRect(x: 790, y: 560, width: 220, height: 40); root.addSubview(button)
        } else {
            let plan = VisibilityPlan(state: state == "peek" ? .peek : .pinned)
            for i in 0..<(state == "first-panel" ? 1 : 3) {
                let frame = state == "first-panel" ? NSRect(x: 680, y: 400, width: 440, height: 360) : NSRect(x: 130+CGFloat(i)*480, y: 330+CGFloat(i % 2)*100, width: 440, height: 360)
                let record = PanelRecord(url: URL(string: "https://example.invalid")!, placement: FractionalFrame(frame: frame, screen: root.bounds.size))
                let view = PanelView(record: record, preview: true); view.frame = frame; view.needsLayout = true; view.applyVisibility(plan)
                root.addSubview(view); view.layoutSubtreeIfNeeded()
                if state == "dormant" && i == 1 { view.previewDormant() }
            }
            if state != "peek" {
                let pill = label("固定中", size: 14); pill.alignment = .center; pill.frame = NSRect(x: 850, y: 1100, width: 100, height: 30); pill.wantsLayer = true; pill.layer?.backgroundColor = NSColor.darkGray.cgColor; pill.layer?.cornerRadius = 14; root.addSubview(pill)
                let add = ActionButton("＋ パネルを追加", action: {}); add.frame = NSRect(x: 790, y: 30, width: 220, height: 40); root.addSubview(add)
            }
            if state == "menu" {
                let box = NSView(frame: NSRect(x: 1430, y: 470, width: 240, height: 160)); box.wantsLayer = true; box.layer?.backgroundColor = NSColor.darkGray.cgColor; box.layer?.cornerRadius = 10
                for (i, title) in ["更新", "既定のアプリで開く", "複製", "削除"].enumerated() { let text = label(title); text.frame = NSRect(x: 18, y: 125-CGFloat(i)*36, width: 210, height: 26); box.addSubview(text) }; root.addSubview(box)
            }
        }
        root.layoutSubtreeIfNeeded()
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw CocoaError(.fileWriteUnknown) }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: directory.appendingPathComponent("overlay-002-\(state).png"))
        host.contentView = nil
    }
}
