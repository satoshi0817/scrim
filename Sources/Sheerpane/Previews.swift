import AppKit
import SheerpaneCore
import SheerpaneAssets

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
            let caption = label("Sheerpane 0.1.0 (6) · TASK-OVERLAY-008 開発中 · 旧ガイドの検証専用（現在の初回起動では表示されません）", size: 16)
            caption.frame = NSRect(x: 180, y: 1060, width: 1440, height: 40); root.addSubview(caption)
        } else if state == "settings" || state == "hotkey-error" {
            let store = SettingsStore(storage: MemorySettingsStorage())
            if state == "hotkey-error" { store.shortcut = .testCopy }
            let settings = SettingsController(store: store, permissionState: { false }, loginService: FakeLoginItemService())
            if state == "hotkey-error" { settings.registrationStatus = .carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus) }
            if let content = settings.window.contentView { content.removeFromSuperview(); content.frame.origin = NSPoint(x: 590, y: state == "gesture-advanced" ? 70 : 180); root.addSubview(content) }
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
    try renderEntryReviews(directory: directory)
}

private func renderEntryReviews(directory: URL) throws {
    for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
        guard let appearance = NSAppearance(named: name) else { throw CocoaError(.fileWriteUnknown) }
        for state in ["layout-wrap", "layout-stack", "layout-settings", "layout-on", "layout-off", "layout-small-screen", "login-off", "login-on", "login-approval", "login-error", "login-unregister-error", "icon", "menu", "settings", "hotkey-error", "hotkey-generic-error", "recording", "first-run", "dock", "gesture-default", "gesture-advanced", "permission-unasked", "permission-denied", "permission-granted", "menu-permitted", "menu-waiting", "menu-secure"] {
            var failure: Error?
            appearance.performAsCurrentDrawingAppearance {
                do { try renderEntryReview(directory: directory, appearance: appearance, theme: theme, state: state) }
                catch { failure = error }
            }
            if let failure { throw failure }
        }
    }
}

private func renderEntryReview(directory: URL, appearance: NSAppearance, theme: String, state: String) throws {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1800, height: 1290))
    root.appearance = appearance; root.wantsLayer = true; root.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    let host = NSWindow(contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
    host.appearance = appearance; host.contentView = root; host.isReleasedWhenClosed = false
    let caption = NSTextField(labelWithString: "Sheerpane 0.1.0 (6) · TASK-OVERLAY-008 開発中 · \(theme) · \(state) · プレビュー（実際のメニューバー表示ではありません）")
    caption.textColor = .secondaryLabelColor; caption.frame = NSRect(x: 50, y: 1210, width: 1650, height: 30); root.addSubview(caption)
    let store = SettingsStore(storage: MemorySettingsStorage())
    store.sameLayoutOnAllDisplays = state != "layout-off"
    if state == "layout-small-screen" || state == "layout-wrap" || state == "layout-stack" {
        let reference = CGSize(width: 1800, height: 1100)
        let small = Backdrop(frame: NSRect(x: 575, y: 280, width: 650, height: state == "layout-stack" ? 400 : 650))
        root.addSubview(small)
        store.panels = (0..<(state == "layout-stack" ? 8 : 4)).map { index in
            PanelRecord(url: URL(string: "https://example.invalid/\(index)")!, placement:
                FractionalFrame(frame: CGRect(x: 20 + index * 440, y: 360, width: 420, height: 320), screen: reference))
        }
        store.sharedLayoutReferenceSize = reference
        let layout = store.layout(for: "uuid:preview-small", screen: small.bounds.size)
        let frames = LayoutFitter.frames(layout: layout, screen: small.bounds.size)
        for (record, frame) in zip(layout.panels, frames) {
            let view = PanelView(record: record, preview: true)
            view.frame = frame; view.applyVisibility(VisibilityPlan(state: .pinned))
            small.addSubview(view); view.needsLayout = true
        }
        let dimensions = label(state == "layout-stack" ? "650×400 · 28pt タイトルバーカスケード · 文字は通常サイズ" : "650×650 · フレーム縮小と本文の折り返し · 文字は通常サイズ", size: 16)
        dimensions.frame = NSRect(x: 450, y: 960, width: 900, height: 30); root.addSubview(dimensions)
    } else if state.hasPrefix("permission-") {
        let value = GesturePermissionState(rawValue: String(state.dropFirst("permission-".count)))!
        let card = GesturePermissionPreviewView(state: value); card.frame.origin = NSPoint(x: 610, y: 440); root.addSubview(card)
    } else if state.hasPrefix("menu-") {
        let content = EntryMenuPreviewView(state: EntryState(shortcut: store.shortcut), showMenu: true,
            gestureStatus: GestureCopy.menu(permitted: state == "menu-permitted", secure: state == "menu-secure"))
        content.frame.origin = NSPoint(x: 570, y: 370); root.addSubview(content)
    } else if state == "icon" || state == "menu" {
        let content = EntryMenuPreviewView(state: EntryState(shortcut: store.shortcut), showMenu: state == "menu")
        content.frame.origin = NSPoint(x: 570, y: 370); root.addSubview(content)
    } else {
        // Explicit fixture preference: identical review output in trial and normal builds.
        store.dockVisible = true
        if state == "hotkey-error" || state == "hotkey-generic-error" { store.shortcut = .testCopy }
        if state == "gesture-advanced" { store.gesture.useFn = true }
        let login = FakeLoginItemService(status: (state == "login-on" || state == "login-unregister-error") ? .enabled : state == "login-approval" ? .requiresApproval : .notRegistered)
        let settings = SettingsController(store: store, permissionState: { false }, loginService: login)
        if state == "login-error" || state == "login-unregister-error" {
            login.failure = NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "登録できませんでした。もう一度お試しください。"])
            settings.loginModel.setEnabled(state == "login-error"); settings.refresh()
        }
        if state == "gesture-advanced" { settings.previewAdvanced() }
        if state == "hotkey-error" { settings.registrationStatus = .carbonFailure(shortcut: .default, status: RegistrationFeedback.alreadyRegisteredStatus) }
        if state == "hotkey-generic-error" { settings.registrationStatus = .carbonFailure(shortcut: .default, status: RegistrationFeedback.internalFailureStatus) }
        if state == "recording" { settings.beginRecording(installMonitor: false) }
        if let content = settings.window.contentView { content.removeFromSuperview(); content.frame.origin = NSPoint(x: 590, y: state == "gesture-advanced" ? 70 : 180); root.addSubview(content) }
        let icon = NSImageView(frame: NSRect(x: 1170, y: 1160, width: 18, height: 18))
        icon.image = StatusIcon.image(warning: settings.registrationStatus != .success); icon.contentTintColor = .labelColor; root.addSubview(icon)
    }
    if state == "icon" || state == "dock" {
        guard let url = StatusIcon.resourceURL(name: "AppIcon", extension: "icns"),
              let image = NSImage(contentsOf: url) else { throw CocoaError(.fileReadNoSuchFile) }
        let appIcon = NSImageView(frame: NSRect(x: 1310, y: 640, width: 128, height: 128))
        appIcon.image = image; appIcon.imageScaling = .scaleProportionallyUpOrDown; root.addSubview(appIcon)
        let appCaption = label("Sheerpane · AppIcon.icns", size: 14)
        appCaption.frame = NSRect(x: 1250, y: 600, width: 300, height: 30); root.addSubview(appCaption)
    }
    root.layoutSubtreeIfNeeded()
    guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw CocoaError(.fileWriteUnknown) }
    root.cacheDisplay(in: root.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    let isR12b = ["layout-wrap", "layout-stack", "layout-settings"].contains(state)
    let filename = isR12b ? "r12b-\(state)-\(theme).png" : state.hasPrefix("layout-") ? "r12-\(state)-\(theme).png" : state.hasPrefix("login-") ? "r11b-\(state)-\(theme).png" : "sheerpane-trial5-\(theme)-\(state).png"
    try data.write(to: directory.appendingPathComponent(filename))
    host.contentView = nil
}
