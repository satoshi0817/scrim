import AppKit
import WebKit
import SheerpaneCore

func label(_ text: String, size: CGFloat = 14) -> NSTextField {
    let v = NSTextField(labelWithString: text); v.font = .systemFont(ofSize: size); v.textColor = .white; return v
}
final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    init(_ title: String, action: @escaping () -> Void) {
        super.init(frame: .zero); self.title = title; bezelStyle = .rounded; target = self; self.action = #selector(run); actionBlock = action
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func run() { actionBlock?() }
}
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var dismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}
final class Backdrop: NSView {
    var dismiss: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) { NSColor(calibratedWhite: 0.035, alpha: 0.76).setFill(); bounds.fill() }
    override func mouseDown(with event: NSEvent) { dismiss?() }
}
final class PanelView: NSView, WKNavigationDelegate {
    let id: UUID
    var url: URL
    var web: WKWebView?
    private var snapshot: NSImage?
    private let image = NSImageView()
    private let dormant = label("休止中")
    private let dormantBadge = NSView()
    private let resumeHint = label("クリックで再開", size: 12)
    private var previewContent: NSView?
    private var previewPlaceholder: NSTextField?
    private let titleLabel = label("ウェブパネル", size: 12)
    private let spinner = NSProgressIndicator()
    private let menuButton: ActionButton
    var touched: (() -> Void)?
    var changed: (() -> Void)?
    var command: ((Int) -> Void)?
    var navigated: ((URL) -> Void)?
    var didSleep: (() -> Void)?
    var constrain: ((CGRect) -> CGRect)?
    private var origin = NSPoint.zero
    private var original = NSRect.zero
    private var edges = 0
    private var moving = false
    private var sleeping = false
    private var epoch = 0
    init(record: PanelRecord, preview: Bool = false) {
        id = record.id; url = record.url; menuButton = ActionButton("…", action: {})
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor; layer?.cornerRadius = 12; layer?.masksToBounds = true
        let icon = label("◈", size: 16); icon.frame = NSRect(x: 14, y: 0, width: 24, height: 28); icon.autoresizingMask = [.minYMargin]; addSubview(icon)
        titleLabel.frame = NSRect(x: 42, y: 0, width: 200, height: 24); titleLabel.autoresizingMask = [.width, .minYMargin]; addSubview(titleLabel)
        menuButton.actionBlock = { [weak self] in self?.showMenu() }; addSubview(menuButton)
        image.imageScaling = .scaleAxesIndependently; image.alphaValue = 0.5; addSubview(image, positioned: .below, relativeTo: titleLabel)
        dormantBadge.wantsLayer = true; dormantBadge.layer?.cornerRadius = 16
        dormantBadge.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor
        dormant.alignment = .center; dormant.font = .systemFont(ofSize: 14, weight: .medium)
        dormantBadge.addSubview(dormant); addSubview(dormantBadge)
        resumeHint.alignment = .center; resumeHint.textColor = .lightGray; addSubview(resumeHint)
        spinner.style = .spinning; spinner.isDisplayedWhenStopped = false; addSubview(spinner)
        if preview {
            let content = NSView(); content.wantsLayer = true
            content.layer?.backgroundColor = NSColor(calibratedRed: 0.25, green: 0.34, blue: 0.39, alpha: 1).cgColor
            let placeholder = label("ひと息つくための、小さな窓", size: 20)
            placeholder.usesSingleLineMode = false; placeholder.maximumNumberOfLines = 0
            placeholder.lineBreakMode = .byWordWrapping; placeholder.cell?.wraps = true
            previewPlaceholder = placeholder; content.addSubview(placeholder)
            previewContent = content; addSubview(content, positioned: .below, relativeTo: image)
        }
        setDormantAppearance(false)
        applyVisibility(VisibilityPlan(state: .hidden))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 42, y: bounds.height-LayoutFitter.titleBarHeight, width: max(40, bounds.width-100), height: 22)
        subviews.first?.frame.origin.y = bounds.height-30
        menuButton.frame = NSRect(x: bounds.width-44, y: bounds.height-32, width: 36, height: 28)
        let content = NSRect(x: 7, y: 7, width: max(0, bounds.width-14), height: max(0, bounds.height-43))
        web?.frame = content; image.frame = content; previewContent?.frame = content
        if let placeholder = previewPlaceholder {
            let width = max(1, content.width-40)
            let height = ceil(placeholder.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 0)
            placeholder.frame = NSRect(x: 20, y: max(0, (content.height-height)/2), width: width, height: height)
        }
        dormantBadge.frame = NSRect(x: content.midX-50, y: content.midY+4, width: 100, height: 32)
        dormant.frame = NSRect(x: 10, y: 5, width: 80, height: 22)
        resumeHint.frame = NSRect(x: 0, y: content.midY-24, width: bounds.width, height: 20)
        spinner.frame = NSRect(x: bounds.midX-12, y: content.midY-56, width: 24, height: 24)
    }
    func applyVisibility(_ plan: VisibilityPlan) { menuButton.isHidden = !plan.showsPanelMenuButton }
    private func setDormantAppearance(_ active: Bool) {
        image.isHidden = !active; dormantBadge.isHidden = !active; resumeHint.isHidden = !active
    }
    func wake() {
        if sleeping, web != nil {
            epoch += 1; sleeping = false; setDormantAppearance(false)
            return
        }
        guard web == nil else { return }
        epoch += 1; sleeping = false; setDormantAppearance(false)
        spinner.startAnimation(nil)
        let view = WKWebView(frame: .zero); web = view; view.navigationDelegate = self
        addSubview(view, positioned: .below, relativeTo: titleLabel); needsLayout = true
        view.load(URLRequest(url: url))
    }
    func sleep() {
        guard !sleeping else { return }
        guard let view = web else { setDormantAppearance(true); return }
        sleeping = true; epoch += 1; let token = epoch
        view.takeSnapshot(with: nil) { [weak self, weak view] picture, _ in
            guard let self, self.epoch == token, self.sleeping else { return }
            self.snapshot = picture; self.image.image = picture; self.setDormantAppearance(true)
            view?.stopLoading(); view?.navigationDelegate = nil; view?.removeFromSuperview(); self.web = nil
            self.spinner.stopAnimation(nil)
            self.didSleep?()
        }
    }
    func previewDormant() {
        layoutSubtreeIfNeeded()
        if let content = previewContent, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let picture = NSImage(size: content.bounds.size); picture.addRepresentation(bitmap)
            snapshot = picture; image.image = picture; content.isHidden = true
        }
        setDormantAppearance(true)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        titleLabel.stringValue = webView.title ?? "ウェブパネル"; spinner.stopAnimation(nil)
        if let current = webView.url, ["http", "https"].contains(current.scheme ?? "") { url = current; navigated?(current) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { spinner.stopAnimation(nil) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { spinner.stopAnimation(nil) }
    private func showMenu() {
        let menu = NSMenu()
        for (index, text) in ["更新", "既定のアプリで開く", "複製", "削除"].enumerated() {
            let item = NSMenuItem(title: text, action: #selector(menuAction(_:)), keyEquivalent: ""); item.tag = index; item.target = self; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.width-40, y: bounds.height-32), in: self)
    }
    @objc private func menuAction(_ item: NSMenuItem) { command?(item.tag) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let p = convert(point, from: superview)
        if p.x < 7 || p.x > bounds.width-7 || p.y < 7 || p.y > bounds.height-7 { return self }
        return hit
    }
    override func mouseDown(with event: NSEvent) {
        touched?(); origin = event.locationInWindow; original = frame
        let p = convert(event.locationInWindow, from: nil)
        edges = (p.x < 7 ? 1 : 0) | (p.x > bounds.width-7 ? 2 : 0) | (p.y < 7 ? 4 : 0) | (p.y > bounds.height-7 ? 8 : 0)
        moving = edges == 0 && p.y >= bounds.height-36
    }
    override func mouseDragged(with event: NSEvent) {
        let dx = event.locationInWindow.x-origin.x, dy = event.locationInWindow.y-origin.y
        var r = original
        if moving { r.origin.x += dx; r.origin.y += dy }
        else {
            if edges & 1 != 0 { let d = min(dx, original.width-240); r.origin.x += d; r.size.width -= d }
            if edges & 2 != 0 { r.size.width = max(240, original.width+dx) }
            if edges & 4 != 0 { let d = min(dy, original.height-160); r.origin.y += d; r.size.height -= d }
            if edges & 8 != 0 { r.size.height = max(160, original.height+dy) }
        }
        if moving || edges != 0 { frame = constrain?(r) ?? r; needsLayout = true }
    }
    override func mouseUp(with event: NSEvent) { if moving || edges != 0 { changed?() }; moving = false; edges = 0 }
}

final class OverlayController {
    let store: SettingsStore
    var pool = PanelPool()
    var records: [PanelRecord]
    var views: [UUID: PanelView] = [:]
    let panel: OverlayPanel
    let root: Backdrop
    private let pill = label("固定中", size: 13)
    private var addButton: ActionButton!
    var state: OverlayState = .hidden
    var onDismiss: (() -> Void)?
    var isSettingsKey: (() -> Bool)?
    private var visibilityRevision = 0
    private var monitor: Any?
    private let displayIdentity = DisplayIdentity()
    private var activeDisplay: String?
    private var activeShared = true
    private var presentationWasFitted = false
    private var ephemeralLayouts: [String: DisplayLayout] = [:]
    private var screenObserver: NSObjectProtocol?
    init(store: SettingsStore) {
        self.store = store; records = Array(store.panels.prefix(PanelPool.maximum))
        root = Backdrop(frame: NSRect(x: 0, y: 0, width: 1800, height: 1169))
        panel = OverlayPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = root; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.alphaValue = 0; panel.ignoresMouseEvents = true
        root.dismiss = { [weak self] in self?.onDismiss?() }; panel.dismiss = root.dismiss
        pill.alignment = .center; pill.wantsLayer = true; pill.layer?.cornerRadius = 12; pill.layer?.backgroundColor = NSColor.darkGray.cgColor; root.addSubview(pill)
        addButton = ActionButton("＋ パネルを追加") { [weak self] in self?.addPrompt() }; root.addSubview(addButton)
        for record in records { install(record); pool.add(record.id) }
        reconcile()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            let ids = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
            self?.displayIdentity.forgetUnavailable(connected: ids)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.state == .pinned, event.window === self.panel else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.onDismiss?(); return nil }
            if event.type == .leftMouseDown {
                let p = self.root.convert(event.locationInWindow, from: nil)
                if let view = self.root.subviews.reversed().compactMap({ $0 as? PanelView }).first(where: { $0.frame.contains(p) }) { self.touch(view.id) }
            }
            return event
        }
    }
    func show(_ next: OverlayState, immediately: Bool = false) {
        let wasHidden = state == .hidden; state = next
        visibilityRevision += 1
        let revision = visibilityRevision
        let plan = VisibilityPlan(state: next)
        panel.ignoresMouseEvents = plan.ignoresMouseEvents
        for view in views.values { view.applyVisibility(plan) }
        layoutChrome()
        if next == .hidden {
            if immediately { panel.alphaValue = 0; return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = plan.fadeDuration; self.panel.animator().alphaValue = plan.alpha
            }, completionHandler: { [weak self] in
                guard let self, self.visibilityRevision == revision, self.state == .hidden,
                      self.panel.isKeyWindow, !(self.isSettingsKey?() ?? false) else { return }
                NSApp.deactivate()
            })
            return
        }
        if wasHidden, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let current = activeDisplay == nil ? nil : displayedLayout()
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            // No screen index/name fallback: missing UUID/number never borrows another display's layout.
            let key = number.map { displayIdentity.key(for: $0) } ?? "ephemeral:" + UUID().uuidString
            let layout = (!store.sameLayoutOnAllDisplays ? ephemeralLayouts[key] : nil)
                ?? store.layout(for: key, screen: screen.frame.size, current: current)
            activeDisplay = key; activeShared = store.sameLayoutOnAllDisplays
            panel.setFrame(screen.frame, display: false); root.frame.size = screen.frame.size
            let selected = Array(layout.panels.prefix(PanelPool.maximum))
            for id in Array(views.keys) where !selected.contains(where: { $0.id == id }) {
                views.removeValue(forKey: id)?.removeFromSuperview(); pool.remove(id)
            }
            records = selected
            let selectedLayout = DisplayLayout(panels: records, referenceSize: layout.referenceSize)
            presentationWasFitted = LayoutFitter.needsFitting(layout: selectedLayout, screen: screen.frame.size)
            for record in records {
                if views[record.id]?.url != record.url { views.removeValue(forKey: record.id)?.removeFromSuperview(); pool.remove(record.id) }
                if views[record.id] == nil { install(record); pool.add(record.id) }
            }
            for (record, frame) in zip(records, LayoutFitter.frames(layout: DisplayLayout(panels: records, referenceSize: layout.referenceSize), screen: screen.frame.size)) {
                views[record.id]?.frame = frame
                if let view = views[record.id] { root.addSubview(view, positioned: .above, relativeTo: nil); view.needsLayout = true }
            }
            reconcile()
        }
        layoutChrome(); panel.alphaValue = plan.alpha; panel.orderFrontRegardless()
        if plan.makeKey { panel.makeKey() }
    }
    func layoutChrome() {
        pill.frame = NSRect(x: root.bounds.midX-40, y: root.bounds.height-52, width: 80, height: 28); pill.isHidden = !VisibilityPlan(state: state).showPinnedPill
        addButton.title = records.isEmpty ? "最初のパネルを追加" : "＋ パネルを追加"
        addButton.frame = NSRect(x: root.bounds.midX-100, y: records.isEmpty ? root.bounds.midY : 24, width: 200, height: 36)
        addButton.isHidden = state != .pinned && !records.isEmpty
    }
    private func install(_ record: PanelRecord) {
        let view = PanelView(record: record); views[record.id] = view; root.addSubview(view)
        view.applyVisibility(VisibilityPlan(state: state))
        view.frame = record.placement.restore(screen: root.bounds.size)
        view.touched = { [weak self] in self?.touch(record.id) }
        view.changed = { [weak self] in self?.saveFrames() }
        view.didSleep = { [weak self] in self?.reconcile() }
        view.navigated = { [weak self] url in
            guard let self, let index = self.records.firstIndex(where: { $0.id == record.id }) else { return }
            self.records[index].url = url; self.persist()
        }
        view.constrain = { [weak self] frame in guard let self else { return frame }; return Placement.constrain(frame, screen: self.root.bounds.size, others: self.views.filter { $0.key != record.id }.map { $0.value.frame }) }
        view.command = { [weak self] command in
            guard let self, let view = self.views[record.id] else { return }
            switch command {
            case 0: self.touch(record.id); view.web?.reload()
            case 1: NSWorkspace.shared.open(view.web?.url ?? view.url)
            case 2: self.add(view.web?.url ?? view.url)
            default: view.removeFromSuperview(); self.views.removeValue(forKey: record.id); self.pool.remove(record.id); self.records.removeAll { $0.id == record.id }; self.persist(); self.layoutChrome()
            }
        }
    }
    private func reconcile() {
        // Snapshot eviction completes before allocating the replacement web view.
        // Pending snapshots count toward the physical four-web-view limit.
        for entry in pool.entries where !entry.live { views[entry.id]?.sleep() }
        for entry in pool.entries where entry.live {
            guard let view = views[entry.id] else { continue }
            if view.web != nil || views.values.filter({ $0.web != nil }).count < PanelPool.liveLimit { view.wake() }
        }
    }
    func touch(_ id: UUID) {
        guard state == .pinned, let view = views[id] else { return }
        root.addSubview(view, positioned: .above, relativeTo: nil); pool.view(id); reconcile()
        if let index = records.firstIndex(where: { $0.id == id }) {
            let record = records.remove(at: index); records.append(record); persist()
        }
    }
    func add(_ url: URL) {
        guard records.count < PanelPool.maximum else { NSSound.beep(); return }
        let n = CGFloat(records.count % 5)
        let record = PanelRecord(url: url, placement: FractionalFrame(frame: NSRect(x: 100+n*48, y: 160+n*40, width: 480, height: 336), screen: root.bounds.size))
        records.append(record); install(record); pool.add(record.id); reconcile(); persist(); layoutChrome()
    }
    private func addPrompt() {
        guard records.count < PanelPool.maximum else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = "ウェブパネルを追加"; alert.addButton(withTitle: "追加"); alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24)); field.placeholderString = "https://example.com"; alert.accessoryView = field
        alert.beginSheetModal(for: panel) { [weak self] response in if response == .alertFirstButtonReturn, let url = SettingsStore.normalize(field.stringValue) { self?.add(url) } }
    }
    private func saveFrames() {
        persist()
    }
    private func displayedLayout() -> DisplayLayout {
        var displayed = records
        for i in displayed.indices {
            if let view = views[displayed[i].id] { displayed[i].placement = FractionalFrame(frame: view.frame, screen: root.bounds.size) }
        }
        return DisplayLayout(panels: displayed, referenceSize: root.bounds.size)
    }
    private func persist() {
        guard let display = activeDisplay else { return }
        let layout = displayedLayout()
        records = layout.panels
        // Web navigation callbacks can arrive after the settings toggle but before show.
        guard activeShared == store.sameLayoutOnAllDisplays else { return }
        if !activeShared && display.hasPrefix("ephemeral:") { ephemeralLayouts[display] = layout }
        else { store.savePresentedLayout(layout, for: display, wasFitted: presentationWasFitted) }
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.orderOut(nil)
    }
}
