import SwiftUI
import AppKit
import Combine
import WebKit
import PDFKit
import QuartzCore
import UniformTypeIdentifiers
import ScrimCore

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
    // The local event monitor owns overlay Escape. Unhandled single presses
    // may still reach this responder after the focused content sees them.
    override func cancelOperation(_ sender: Any?) {}

    override func sendEvent(_ event: NSEvent) {
        guard let root = contentView as? Backdrop, root.editing else { super.sendEvent(event); return }
        switch event.type {
        case .cursorUpdate, .mouseMoved, .mouseEntered, .mouseExited:
            // AppKit can ask a WebKit or text child for its cursor even when the panel owns the hit.
            if let panel = root.hitTest(event.locationInWindow) as? PanelView {
                if event.type != .cursorUpdate { super.sendEvent(event) }
                panel.editingCursor(at: panel.convert(event.locationInWindow, from: nil)).set()
                return
            }
        default: break
        }
        super.sendEvent(event)
    }
}
final class Backdrop: NSView {
    var dismiss: (() -> Void)?
    var editing = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.035, alpha: 0.76).setFill(); bounds.fill()
        if editing {
            NSColor.white.withAlphaComponent(0.35).setFill()
            let grid = PanelGrid(screen: bounds.size), step = grid.step
            for column in 0...Placement.gridColumns {
                for row in 0...Placement.gridRows {
                    NSBezierPath(ovalIn: NSRect(x: (column == Placement.gridColumns ? grid.bounds.maxX : grid.bounds.minX+CGFloat(column)*step.width)-1.5,
                                               y: (row == Placement.gridRows ? grid.bounds.maxY : grid.bounds.minY+CGFloat(row)*step.height)-1.5, width: 3, height: 3)).fill()
                }
            }
        }
    }
    override func mouseDown(with event: NSEvent) { dismiss?() }
}
private extension NSView {
    /// Commit geometry immediately so hit testing and saved frames always use the destination.
    func settleFrame(_ destination: CGRect) {
        guard frame != destination else { return }
        let start = layer?.presentation()?.frame ?? frame
        frame = destination
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer,
              start.width > 0, start.height > 0, destination.width > 0, destination.height > 0 else { return }
        let anchor = layer.anchorPoint
        let dx = start.minX - destination.minX + anchor.x * (start.width - destination.width)
        let dy = start.minY - destination.minY + anchor.y * (start.height - destination.height)
        let motion = CABasicAnimation(keyPath: "transform")
        motion.fromValue = CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0),
                                              start.width / destination.width, start.height / destination.height, 1)
        motion.toValue = CATransform3DIdentity
        motion.duration = 0.16
        motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(motion, forKey: "layoutSettle")
    }
}

private struct PanelResizeEdges: OptionSet {
    let rawValue: Int
    static let left = Self(rawValue: 1 << 0)
    static let right = Self(rawValue: 1 << 1)
    static let bottom = Self(rawValue: 1 << 2)
    static let top = Self(rawValue: 1 << 3)

    private static let fallingDiagonal = diagonalCursor("arrow.up.left.and.arrow.down.right")
    private static let risingDiagonal = diagonalCursor("arrow.up.right.and.arrow.down.left")

    private static func diagonalCursor(_ symbol: String) -> NSCursor {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold)) else { return .resizeLeftRight }
        let size = image.size
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }

    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case .left: position = .left
            case .right: position = .right
            case .bottom: position = .bottom
            case .top: position = .top
            case [.left, .bottom]: position = .bottomLeft
            case [.left, .top]: position = .topLeft
            case [.right, .bottom]: position = .bottomRight
            case [.right, .top]: position = .topRight
            default: return .openHand
            }
            return .frameResize(position: position, directions: .all)
        }
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case [.left, .top], [.right, .bottom]: return Self.fallingDiagonal
        case [.right, .top], [.left, .bottom]: return Self.risingDiagonal
        default: return .openHand
        }
    }
}

final class PanelView: NSView, WKNavigationDelegate, PDFViewDelegate {
    let id: UUID
    var url: URL
    var web: WKWebView?
    private var document: NSView?
    var isLive: Bool { web != nil || document != nil }
    private var widgetPanel: NativeWidgetPanel?
    private var calendarTodayPending = false
    private var webDisplayMode: WebDisplayMode = .desktop
    private var weatherShowsHourly = true
    private let fileReadAccessRoot: URL?
    private let notes: PanelNotes?
    private let weatherProvider: any WeatherProviding
    private var fileError: FilePanelErrorView?
    private(set) var fileState: FilePanelState
    private let image = NSImageView()
    private let dormant = label("休止中")
    private let dormantBadge = NSView()
    private let resumeHint = label("クリックで再開", size: 12)
    private var previewContent: NSView?
    private var previewPlaceholder: NSTextField?
    let browser = BrowserWindows()
    private let websiteDataStore: WKWebsiteDataStore
    private let spinner = NSProgressIndicator()
    /// Edit mode: a centered menu label, and a blur over the content while hovered. A click anywhere on the
    /// panel opens the menu and a drag moves it; both are handled by this view's own mouse events.
    private let editHint = PanelEditHint()
    private let editBlur = PanelBlurView()
    private(set) var currentMenu: PanelMenuModel?
    private var blurCapture = 0
    private var capturingBlur = false
    var isShowingMenu: Bool { currentMenu != nil }
    var hasBlurSnapshot: Bool { editBlur.hasSnapshot }
    var presentSettings: ((PanelView, PanelMenuModel, NotionTasksModel?, AnyView?) -> Bool)?
    var dismissSettings: (() -> Void)?
    var saveWebSettings: ((URL, WebDisplayMode) -> Void)?
    private var settingsNotion: NotionTasksModel?
    private var hoverArea: NSTrackingArea?
    private var hovering = false { didSet { if hovering != oldValue { updateEditChrome() } } }
    private var clickCandidate = false
    var touched: (() -> Void)?
    var changed: (() -> Void)?
    var didOpenWebLink: (() -> Void)?
    var command: ((Int) -> Void)?
    var canEditContent = false
    var navigated: ((URL) -> Void)?
    var didSleep: (() -> Void)?
    var constrain: ((CGRect) -> CGRect)?
    private var origin = NSPoint.zero
    private var original = NSRect.zero
    private var edges: PanelResizeEdges = []
    private var moving = false
    private var sleeping = false
    private var epoch = 0
    private(set) var editing = false
    private var visibility = VisibilityPlan(state: .hidden)
    init(record: PanelRecord, preview: Bool = false, websiteDataStore: WKWebsiteDataStore = .default(), fileReadAccessRoot: URL? = nil, weatherProvider: any WeatherProviding = WeatherService.shared, notes: PanelNotes? = nil) {
        self.notes = notes
        self.weatherProvider = weatherProvider
        self.fileReadAccessRoot = fileReadAccessRoot
        self.websiteDataStore = websiteDataStore
        id = record.id; url = WebPanelPolicy.launchURL(record.url); fileState = FilePanelState(url: notes?.files.contentURL(for: url) ?? url)
        super.init(frame: .zero)
        browser.onLastWindowClosed = { [weak self] in self?.didSleep?() }
        browser.openWebLink = { [weak self] url in
            DefaultBrowser.open(url) { self?.didOpenWebLink?() }
        }
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; layer?.cornerRadius = 12; layer?.masksToBounds = true
        editBlur.isHidden = true; editBlur.alphaValue = 0; addSubview(editBlur)
        editHint.press = { [weak self] in self?.showMenu() }; editHint.alphaValue = 0; addSubview(editHint)
        image.imageScaling = .scaleAxesIndependently; image.alphaValue = 0.5; addSubview(image, positioned: .below, relativeTo: editBlur)
        dormantBadge.wantsLayer = true; dormantBadge.layer?.cornerRadius = 16
        dormantBadge.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor
        dormant.alignment = .center; dormant.font = .systemFont(ofSize: 14, weight: .medium)
        dormantBadge.addSubview(dormant); addSubview(dormantBadge)
        resumeHint.alignment = .center; resumeHint.textColor = .lightGray; addSubview(resumeHint)
        spinner.style = .spinning; spinner.isDisplayedWhenStopped = false; addSubview(spinner)
        if preview {
            let content = NSView(); content.wantsLayer = true
            content.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
            let placeholder = label("ひと息つくための、小さな窓", size: 20)
            placeholder.usesSingleLineMode = false; placeholder.maximumNumberOfLines = 0
            placeholder.lineBreakMode = .byWordWrapping; placeholder.cell?.wraps = true
            previewPlaceholder = placeholder; content.addSubview(placeholder)
            previewContent = content; addSubview(content, positioned: .below, relativeTo: image)
        }
        setDormantAppearance(false)
        applyVisibility(VisibilityPlan(state: .hidden))
        if fileState.source == .unreadable { showFileError(loadFailed: false) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        updateAccent()
    }
    func updateAccent() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = ScrimTheme.shared.accent.nativeInk.cgColor
        }
        needsDisplay = true
    }
    func handleTaskDetailEscape() -> Bool {
        guard let widget = widgetPanel, widget.model.spec.kind == .notionTasks else { return false }
        let model = widget.model.notion
        guard let detail = model.detail else { return false }
        if detail.editingBlock != nil { detail.cancelEdit() }
        else if detail.editingTitle { detail.cancelTitleEdit() }
        else if detail.confirmingDelete != nil { detail.confirmingDelete = nil }
        else { model.closeDetail() }
        return true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        widgetPanel?.setActive(window != nil && visibility.alpha > 0)
    }
    override func layout() {
        super.layout()
        editBlur.frame = bounds
        let hint = editHint.fittingSize
        editHint.frame = NSRect(x: (bounds.width-hint.width)/2, y: (bounds.height-hint.height)/2, width: hint.width, height: hint.height)
        let content = bounds
        if let web {
            let width = webDisplayMode == .mobile && !url.isFileURL ? min(390, content.width) : content.width
            web.frame = NSRect(x: content.midX-width/2, y: content.minY, width: width, height: content.height)
        }
        document?.frame = content
        fileError?.frame = content
        let imageWidth = webDisplayMode == .mobile && ["http", "https"].contains(url.scheme ?? "") ? min(390, content.width) : content.width
        image.frame = NSRect(x: content.midX-imageWidth/2, y: content.minY, width: imageWidth, height: content.height)
        previewContent?.frame = content
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
    func applyVisibility(_ plan: VisibilityPlan) {
        visibility = plan
        updateEditChrome()
        browser.setVisible(plan.alpha > 0 && !plan.ignoresMouseEvents)
        widgetPanel?.setActive(plan.alpha > 0)
        if plan.alpha == 0, let memo = document as? NativeNotePanel, window?.firstResponder === memo.editor {
            window?.makeFirstResponder(nil)
        }
        if plan.alpha == 0, WebPanelPolicy.isNotionCalendar(url) {
            calendarTodayPending = false
            web?.evaluateJavaScript(CalendarWebNavigation.cancel, completionHandler: nil)
        }
    }
    func setWeatherShowsHourly(_ value: Bool) {
        weatherShowsHourly = value; widgetPanel?.model.setShowsHourly(value)
    }
    func setWebDisplayMode(_ mode: WebDisplayMode) {
        guard mode != webDisplayMode else { return }
        webDisplayMode = mode
        if let web, !url.isFileURL {
            web.customUserAgent = mode == .mobile ? Self.mobileUserAgent : nil
            needsLayout = true; layoutSubtreeIfNeeded()
            web.reload()
        }
    }
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    func prepareAgendaPresentation(resetScroll: Bool) {
        widgetPanel?.model.upcoming?.beginPresentation(resetScroll: resetScroll)
    }
    func returnCalendarToToday() {
        guard WebPanelPolicy.isNotionCalendar(url) else { return }
        calendarTodayPending = true
        if let web, !web.isLoading, let current = web.url, WebPanelPolicy.canReturnToToday(current) {
            calendarTodayPending = false
            web.evaluateJavaScript(CalendarWebNavigation.today, completionHandler: nil)
        }
    }
    func setEditing(_ value: Bool) {
        editing = value; moving = false; edges = []
        widgetPanel?.setEditing(value)
        (document as? NativeNotePanel)?.setLayoutEditing(value)
        layer?.borderWidth = value ? 3 : 0
        updateAccent()
        window?.invalidateCursorRects(for: self)
        if let window { hovering = value && bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        if !value && isShowingMenu { dismissSettings?() }
        applyVisibility(visibility)
    }
    /// Edit mode only, and not while a widget shows its own settings face: hovering blurs the panel and shows
    /// the menu pill on top; the blur stays while the panel is dragged or resized, and behind the menu face.
    private(set) var editChrome = (pill: false, blur: false)
    private func updateEditChrome() {
        let available = editing && visibility.showsPanelMenuButton
        let menuOpen = isShowingMenu
        let dragging = (moving && !clickCandidate) || !edges.isEmpty
        let next = (pill: available && !menuOpen && hovering && !dragging,
                    blur: available && (menuOpen || hovering || dragging || clickCandidate))
        editHint.isHidden = !available
        editBlur.isHidden = !available
        guard next != editChrome else { return }
        if next.blur && !editChrome.blur { captureBlur() }
        editChrome = next
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            editHint.animator().alphaValue = next.pill ? 1 : 0
            editBlur.animator().alphaValue = next.blur ? 1 : 0
        }, completionHandler: { [weak self] in
            // Free the snapshot as soon as the blur is gone; the next hover takes a fresh one.
            guard let self, !self.editChrome.blur else { return }
            self.blurCapture += 1; self.editBlur.setSnapshot(nil)
        })
        needsLayout = true
    }
    /// Snapshots what the panel shows (web content comes from WebKit, the rest from the view itself) for the blur.
    private func captureBlur() {
        blurCapture += 1; let token = blurCapture
        editBlur.setSnapshot(nil)
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        let overlays = [editBlur, editHint] as [NSView]
        let wasHidden = overlays.map(\.isHidden)
        // Leave out the overlays and the blue edit border and corner handles, which would bleed into the blur.
        overlays.forEach { $0.isHidden = true }
        let border = layer?.borderWidth ?? 0
        layer?.borderWidth = 0; capturingBlur = true
        // Quarter resolution: the result is blurred anyway, and full Retina snapshots cost tens of MB per panel.
        let base = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: max(1, Int(bounds.width * PanelBlurView.captureScale)),
                                    pixelsHigh: max(1, Int(bounds.height * PanelBlurView.captureScale)), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        base?.size = bounds.size
        if let base { cacheDisplay(in: bounds, to: base) }
        layer?.borderWidth = border; capturingBlur = false
        zip(overlays, wasHidden).forEach { $0.isHidden = $1 }
        guard let base else { return }
        guard let web, !sleeping, !web.isHidden else { editBlur.setSnapshot(base); return }
        let webFrame = web.frame
        let small = WKSnapshotConfiguration(); small.snapshotWidth = NSNumber(value: Double(webFrame.width * PanelBlurView.captureScale))
        web.takeSnapshot(with: small) { [weak self] picture, _ in
            guard let self, token == self.blurCapture else { return }
            if let picture, let context = NSGraphicsContext(bitmapImageRep: base) {
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                picture.draw(in: webFrame)
                NSGraphicsContext.restoreGraphicsState()
            }
            self.editBlur.setSnapshot(base)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = editing }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if editing && !capturingBlur {
            ScrimTheme.shared.accent.nativeInk.setFill()
            for x in [CGFloat(0), bounds.width-10] {
                for y in [CGFloat(0), bounds.height-10] { NSRect(x: x, y: y, width: 10, height: 10).fill() }
            }
        }
    }
    private func setDormantAppearance(_ active: Bool) {
        image.isHidden = !active; dormantBadge.isHidden = !active; resumeHint.isHidden = !active
    }
    func wake() {
        if sleeping, web != nil {
            epoch += 1; sleeping = false; setDormantAppearance(false)
            return
        }
        guard web == nil, document == nil else { return }
        fileState = FilePanelState(url: notes?.files.contentURL(for: url) ?? url); fileError?.isHidden = true
        if let notes, notes.files.noteURL(for: url) != nil {
            do {
                let memo = NativeNotePanel(note: try notes.open(url), notes: notes, openWebLink: browser.openWebLink)
                memo.setLayoutEditing(editing)
                document = memo; addSubview(memo, positioned: .below, relativeTo: image)
                setDormantAppearance(false); needsLayout = true
            } catch { showFileError(loadFailed: fileState.source != .unreadable) }
            return
        }
        switch fileState.source {
        case .unreadable: showFileError(loadFailed: false); return
        case .pdf(let file):
            guard let pdf = PDFDocument(url: file), pdf.pageCount > 0 else { showFileError(); return }
            let view = PDFView(); view.delegate = self; view.document = pdf; view.autoScales = true
            document = view; addSubview(view, positioned: .below, relativeTo: image)
            setDormantAppearance(false); needsLayout = true; return
        case .text(let file):
            guard let text = try? PanelDocumentStorage.readText(at: file) else { showFileError(); return }
            let scroll = NativeTextPanel(content: text, openWebLink: browser.openWebLink)
            document = scroll; addSubview(scroll, positioned: .below, relativeTo: image)
            setDormantAppearance(false); needsLayout = true; return
        case .widget(let spec):
            let widget = NativeWidgetPanel(spec: spec, provider: weatherProvider, openWebLink: browser.openWebLink)
            if let zones = UserDefaults.standard.stringArray(forKey: digitalZonesKey), !zones.isEmpty {
                widget.model.digitalZones = zones
            }
            widget.model.onClockStyleChange = { [weak self] style in
                guard let self else { return }
                self.url = WidgetSpec(kind: .clock, clockStyle: style).url
                self.fileState = FilePanelState(url: self.url)
                self.navigated?(self.url)
            }
            if let agenda = widget.model.upcoming {
                agenda.onConfigurationChange = { [weak self, weak agenda] in
                    guard let self, let agenda else { return }
                    self.url = WidgetSpec(kind: .upcoming, calendarIDs: agenda.selectedCalendarIDs, agendaDays: agenda.displayDays, excludedKeywords: agenda.excludedKeywords).url
                    self.fileState = FilePanelState(url: self.url)
                    self.navigated?(self.url)
                }
            }
            if spec.kind == .notionTasks {
                widget.model.notion.onOpenPage = browser.openWebLink
                widget.model.notion.onRequestConfiguration = { [weak self] in self?.showSettings(fromNotion: true) }
                widget.model.notion.onFinishConfiguration = { [weak self] in self?.dismissSettings?() }
                // Mapping and saved filters both live in the panel URL.
                let save = { [weak self, weak widget] in
                    guard let self, let notion = widget?.model.notion, let mapping = notion.mapping else { return }
                    self.url = WidgetSpec(kind: .notionTasks, notionTasks: mapping, notionFilter: notion.filter).url
                    self.fileState = FilePanelState(url: self.url)
                    self.navigated?(self.url)
                }
                widget.model.notion.onConfigurationChange = { _ in save() }
                widget.model.notion.onFilterChange = { _ in save() }
            }
            widgetPanel = widget; document = widget
            widget.model.setShowsHourly(weatherShowsHourly)
            widget.setEditing(editing)
            addSubview(widget, positioned: .below, relativeTo: image)
            widget.setActive(visibility.alpha > 0)
            setDormantAppearance(false); needsLayout = true; return
        default: break
        }
        epoch += 1; sleeping = false; setDormantAppearance(false)
        spinner.startAnimation(nil)
        let configuration = BrowserWindows.panelConfiguration(dataStore: websiteDataStore)
        let view = PanelWebView(frame: .zero, configuration: configuration)
        // A live WebView takes a fresh snapshot the next time it sleeps.
        image.image = nil
        if webDisplayMode == .mobile && !url.isFileURL { view.customUserAgent = Self.mobileUserAgent }
        web = view; view.navigationDelegate = self; view.uiDelegate = browser
        view.allowsBackForwardNavigationGestures = true
        addSubview(view, positioned: .below, relativeTo: image); needsLayout = true
        if case .html(let file) = fileState.source {
            view.loadFileURL(file, allowingReadAccessTo: fileReadAccessRoot ?? file.deletingLastPathComponent())
        } else { view.load(URLRequest(url: url)) }
    }
    private func showFileError(loadFailed: Bool = true) {
        if loadFailed { fileState.loadFailed() }
        let errorView = fileError ?? FilePanelErrorView(frame: bounds)
        if fileError == nil { addSubview(errorView); fileError = errorView }
        errorView.apply(fileState); web?.stopLoading(); web?.navigationDelegate = nil
        web?.removeFromSuperview(); web = nil; document?.removeFromSuperview(); document = nil
        spinner.stopAnimation(nil); setDormantAppearance(false); errorView.isHidden = false; needsLayout = true
    }
    func reloadContent() {
        if let widgetPanel { widgetPanel.reload(); return }
        if let memo = document as? NativeNotePanel, let notes {
            guard notes.save(memo.note) else { return }
            let source = notes.files.contentURL(for: url)
            do {
                let body = try PanelDocumentStorage.readText(at: source)
                memo.note.content.performEditingTransaction { memo.note.text.setAttributedString(body) }
                memo.note.undo.removeAllActions()
            } catch {
                fileState = FilePanelState(url: source)
                showFileError(loadFailed: fileState.source != .unreadable)
            }
            return
        }
        browser.closeAll()
        if let web { discard(web) }; web = nil
        document?.removeFromSuperview(); document = nil; wake()
    }
    /// Frees the web page while the overlay is hidden. No snapshot: hidden windows do not render one, and the
    /// next show reloads the page anyway. Logins in progress (open popups) are kept.
    func releaseWeb() {
        guard let view = web, !browser.hasOpenWindows else { return }
        epoch += 1; sleeping = false; web = nil
        spinner.stopAnimation(nil)
        discard(view)
    }
    /// For a panel that is deleted, replaced or evicted: closes its popups and frees its web page.
    func discardWeb() {
        browser.closeAll()
        guard let view = web else { return }
        epoch += 1; sleeping = false; web = nil
        discard(view)
    }
    /// Removing a web view is not enough: AppKit can keep one that once had keyboard focus alive (text-selection
    /// gesture tracking), and with it the page and its content process memory. BlankPageUnloader moves the view
    /// to a blank page in a fresh process, so WebKit releases the old one.
    private func discard(_ view: WKWebView) {
        view.uiDelegate = nil; view.stopLoading()
        if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
        BlankPageUnloader.unload(view)
    }
    func sleep() {
        // Do not evict the opener while a login flow still uses window.opener.
        guard !browser.hasOpenWindows else { return }
        if fileState.source == .unreadable { return }
        if let document {
            if let memo = document as? NativeNotePanel, notes?.save(memo.note) == false { return }
            widgetPanel?.setActive(false); widgetPanel = nil
            if let bitmap = document.bitmapImageRepForCachingDisplay(in: document.bounds) {
                document.cacheDisplay(in: document.bounds, to: bitmap)
                let picture = NSImage(size: document.bounds.size); picture.addRepresentation(bitmap)
                image.image = picture
            }
            document.removeFromSuperview(); self.document = nil
            setDormantAppearance(true); return
        }
        guard !sleeping else { return }
        guard let view = web else { setDormantAppearance(true); return }
        sleeping = true; epoch += 1; let token = epoch
        view.takeSnapshot(with: nil) { [weak self, weak view] picture, _ in
            guard let self, self.epoch == token, self.sleeping else { return }
            self.image.image = picture; self.setDormantAppearance(true)
            if let view { self.discard(view) }; self.web = nil
            self.spinner.stopAnimation(nil)
            self.didSleep?()
        }
    }
    func previewDormant() {
        layoutSubtreeIfNeeded()
        if let content = previewContent, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let picture = NSImage(size: content.bounds.size); picture.addRepresentation(bitmap)
            image.image = picture; content.isHidden = true
        }
        setDormantAppearance(true)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(browser.openActivatedLink(action, in: webView) ? .cancel : .allow)
    }
    func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
        openExternally(url)
    }
    func openExternally(_ url: URL) {
        if DefaultBrowser.supports(url) { browser.openWebLink(url) }
        else { NSWorkspace.shared.open(url) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimation(nil)
        if !url.isFileURL, let current = webView.url, ["http", "https"].contains(current.scheme ?? "") {
            let saved = WebPanelPolicy.savedURL(current, previous: url)
            if saved != url { url = saved; navigated?(saved) }
        }
        if calendarTodayPending, visibility.alpha > 0, let current = webView.url, WebPanelPolicy.canReturnToToday(current) {
            calendarTodayPending = false
            webView.evaluateJavaScript(CalendarWebNavigation.today, completionHandler: nil)
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { spinner.stopAnimation(nil); if url.isFileURL && (error as NSError).code != NSURLErrorCancelled { showFileError() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { spinner.stopAnimation(nil); if url.isFileURL && (error as NSError).code != NSURLErrorCancelled { showFileError() } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if url.isFileURL { showFileError() }
    }
    private func showMenu() { showSettings() }

    func showSettings(fromNotion: Bool = false) {
        guard (editing || fromNotion), currentMenu == nil, let presentSettings else { return }
        let spec = WidgetSpec(url: url)
        let notion = spec?.kind == .notionTasks ? widgetPanel?.model.notion : nil
        guard !fromNotion || notion != nil else { return }
        let settings: AnyView?
        if let agenda = widgetPanel?.model.upcoming {
            settings = AnyView(UpcomingEventsSettings(model: agenda))
        } else if spec?.kind == .worldclock {
            settings = AnyView(WorldClockSettings())
        } else if DefaultBrowser.supports(url) {
            settings = AnyView(WebPanelSettings(address: url.absoluteString, mode: webDisplayMode) { [weak self] url, mode in
                self?.saveWebSettings?(url, mode)
            })
        } else {
            settings = nil
        }
        let menu = makeMenuModel(spec: spec)
        guard presentSettings(self, menu, notion, settings) else { return }
        currentMenu = menu
        settingsNotion = notion
        notion?.beginConfiguring()
        updateEditChrome()
    }

    func endSettings() {
        currentMenu = nil
        if settingsNotion?.isConfiguring == true { settingsNotion?.cancelConfiguring() }
        settingsNotion = nil
        updateEditChrome()
    }

    private func makeMenuModel(spec: WidgetSpec?) -> PanelMenuModel {
        var actions = [PanelMenuItem(tag: 0, title: "更新", symbol: "arrow.clockwise")]
        if WebPanelPolicy.isNotionCalendar(url) {
            actions.append(PanelMenuItem(tag: 23, title: "今日に戻す", symbol: "calendar.badge.clock"))
        }
        if canEditContent {
            let title = notes?.files.noteURL(for: url) == nil ? "内容を編集…" : "メモを編集"
            actions.append(PanelMenuItem(tag: 4, title: title, symbol: "square.and.pencil"))
        } else if case .text = fileState.source {
            actions.append(PanelMenuItem(tag: 27, title: "メモとして複製", symbol: "doc.on.doc"))
        }
        if spec == nil {
            let title = DefaultBrowser.supports(url) ? "デフォルトブラウザで開く" : "既定のアプリで開く"
            actions.append(PanelMenuItem(tag: 1, title: title, symbol: "arrow.up.forward.app"))
        }
        actions.append(PanelMenuItem(tag: 2, title: "複製", symbol: "plus.square.on.square"))
        let title = spec?.title ?? (url.isFileURL ? url.lastPathComponent : web?.title ?? url.host ?? "Webパネル")
        let model = PanelMenuModel(title: title, actions: actions,
                                   remove: PanelMenuItem(tag: 3, title: "パネルを削除", symbol: "trash", destructive: true),
                                   clockStyle: spec?.kind == .clock ? widgetPanel?.model.clockStyle : nil,
                                   digitalZones: widgetPanel?.model.digitalZones ?? [])
        model.choose = { [weak self] tag in self?.chooseMenuItem(tag) }
        model.toggleZone = { [weak self, weak model] zone in
            self?.toggleDigitalZone(zone); model?.digitalZones = self?.widgetPanel?.model.digitalZones ?? []
        }
        model.close = { [weak self] in self?.dismissSettings?() }
        return model
    }
    func chooseMenuItem(_ tag: Int) {
        guard editing, let currentMenu else { return }
        if tag == 20 || tag == 21 {
            performMenuAction(tag)
            currentMenu.clockStyle = widgetPanel?.model.clockStyle
        } else {
            dismissSettings?()
            performMenuAction(tag)
        }
    }

    private var digitalZonesKey: String { "digitalClock.zones." + id.uuidString }
    private func toggleDigitalZone(_ zone: String) {
        guard editing, let model = widgetPanel?.model else { return }
        if model.digitalZones.contains(zone) {
            guard model.digitalZones.count > 1 else { return }
            model.digitalZones.removeAll { $0 == zone }
        } else {
            model.digitalZones.append(zone)
        }
        UserDefaults.standard.set(model.digitalZones, forKey: digitalZonesKey)
    }

    func performMenuAction(_ tag: Int) {
        guard editing else { return }
        switch tag {
        case 20: widgetPanel?.model.clockStyle = .analog
        case 21: widgetPanel?.model.clockStyle = .digital
        case 23: returnCalendarToToday()
        default: command?(tag)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard editing else { return super.hitTest(point) }
        let p = convert(point, from: superview)
        guard !isHidden, bounds.contains(p) else { return nil }
        return self
    }
    private func resizeEdges(at point: NSPoint) -> PanelResizeEdges {
        // Keep a generous corner target without taking over the middle of small panels.
        let x = min(point.x - bounds.minX, bounds.maxX - point.x)
        let y = min(point.y - bounds.minY, bounds.maxY - point.y)
        let horizontal: PanelResizeEdges = point.x < bounds.midX ? .left : .right
        let vertical: PanelResizeEdges = point.y < bounds.midY ? .bottom : .top
        if x < min(24, bounds.width / 3), y < min(24, bounds.height / 3) {
            return [horizontal, vertical]
        }
        if x < min(14, bounds.width / 3) { return horizontal }
        if y < min(14, bounds.height / 3) { return vertical }
        return []
    }
    func editingCursor(at point: NSPoint) -> NSCursor {
        resizeEdges(at: point).cursor
    }
    override func mouseDown(with event: NSEvent) {
        guard editing else { touched?(); return }
        dropFrame = nil; touched?(); origin = event.locationInWindow; original = frame
        edges = resizeEdges(at: convert(event.locationInWindow, from: nil))
        moving = edges.isEmpty
        clickCandidate = moving
        updateEditChrome()
    }
    override func rightMouseDown(with event: NSEvent) {
        guard editing else { super.rightMouseDown(with: event); return }
        touched?(); showMenu()
    }
    private var dropFrame: CGRect?
    override func mouseDragged(with event: NSEvent) {
        guard editing else { return }
        let dx = event.locationInWindow.x-origin.x, dy = event.locationInWindow.y-origin.y
        // A press that stays within a few points is a click (menu), not a move.
        if clickCandidate {
            guard hypot(dx, dy) >= Self.dragThreshold else { return }
            clickCandidate = false; updateEditChrome()
        }
        var r = original
        if moving { r.origin.x += dx; r.origin.y += dy }
        else {
            if edges.contains(.left) { let d = min(dx, original.width-1); r.origin.x += d; r.size.width -= d }
            if edges.contains(.right) { r.size.width = max(1, original.width+dx) }
            if edges.contains(.bottom) { let d = min(dy, original.height-1); r.origin.y += d; r.size.height -= d }
            if edges.contains(.top) { r.size.height = max(1, original.height+dy) }
        }
        if moving || !edges.isEmpty {
            dropFrame = constrain?(r) ?? r
            layer?.removeAnimation(forKey: "layoutSettle")
            frame = r
            needsLayout = true
        }
    }
    static let dragThreshold: CGFloat = 4
    override func mouseUp(with event: NSEvent) {
        let click = editing && clickCandidate
        if editing, let dropFrame { settleFrame(dropFrame); changed?() }
        dropFrame = nil
        moving = false
        edges = []
        clickCandidate = false
        updateEditChrome()
        if click { showMenu() }
    }
    deinit { browser.closeAll() }

    func focusNote() {
        wake()
        if let memo = document as? NativeNotePanel { window?.makeFirstResponder(memo.editor) }
    }
}

final class OverlayController {
    let store: SettingsStore
    private let websiteDataStore: WKWebsiteDataStore
    let documentStorage: PanelDocumentStorage
    let notes: PanelNotes
    private let weatherProvider: any WeatherProviding
    var pool = PanelPool()
    var records: [PanelRecord]
    var views: [UUID: PanelView] = [:]
    let panel: OverlayPanel
    let root: Backdrop
    private let pill = label("固定中", size: 13)
    private let toolbar = OverlayControls(frame: .zero)
    private var addButton: ActionButton!
    private var editButton: ActionButton!
    private(set) var editing = false
    var state: OverlayState = .hidden
    var onDismiss: (() -> Void)?
    private var dialog: OverlayDialogBackdrop?
    private var accentObservation: AnyCancellable?
    private var lastEscape: TimeInterval?
    private var clickedPanelID: UUID?
    private var usesDoubleEscape: Bool
    private let actionSelection = ActionSelection()
    private weak var embeddedSettings: SettingsController?
    private(set) weak var panelWithSettings: PanelView?
    private var showingGallery = false
    var showingActions: Bool { dialog != nil && embeddedSettings == nil && !showingGallery && panelWithSettings == nil }
    private weak var previousResponder: NSResponder?
    private var galleryDrag: (originals: [UUID: CGRect], marker: NSView)?
    private func clearGalleryDrag() {
        guard let drag = galleryDrag else { return }
        galleryDrag = nil
        drag.marker.removeFromSuperview()
        for (id, frame) in drag.originals { views[id]?.settleFrame(frame) }
        dialog?.alphaValue = 1
    }
    func closeDialog() {
        clearGalleryDrag()
        guard let dialog else { return }
        embeddedSettings?.finishEmbedded()
        embeddedSettings = nil
        showingGallery = false
        panelWithSettings?.endSettings()
        panelWithSettings = nil
        dialog.removeFromSuperview()
        self.dialog = nil
        panel.makeFirstResponder(previousResponder ?? root)
        previousResponder = nil
    }
    private func presentDialog<V: View>(_ content: V, size: NSSize, expandingFrom source: NSRect? = nil) {
        let shield = OverlayDialogBackdrop(frame: root.bounds)
        shield.autoresizingMask = [.width, .height]
        shield.wantsLayer = true
        shield.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        shield.close = { [weak self] in self?.closeDialog() }
        let host = NSHostingView(rootView: content.scrimTint())
        let w = min(size.width, root.bounds.width - 24), h = min(size.height, root.bounds.height - 24)
        host.frame = NSRect(x: (root.bounds.width-w)/2, y: (root.bounds.height-h)/2, width: w, height: h)
        host.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        shield.dialogContent = host
        shield.addSubview(host)
        previousResponder = panel.firstResponder
        root.addSubview(shield, positioned: .above, relativeTo: nil)
        dialog = shield
        panel.makeFirstResponder(shield)
        if let source {
            host.wantsLayer = true
            host.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 1
            }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = host.layer {
                let scale = max(0.72, min(0.96, source.width / w, source.height / h))
                let origin = CGPoint(x: source.midX - host.frame.midX, y: source.midY - host.frame.midY)
                let pivot = CGPoint(x: w * (0.5 - layer.anchorPoint.x), y: h * (0.5 - layer.anchorPoint.y))
                let transform = CATransform3DMakeAffineTransform(
                    CGAffineTransform(translationX: origin.x + pivot.x * (1 - scale), y: origin.y + pivot.y * (1 - scale))
                        .scaledBy(x: scale, y: scale))
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = transform
                animation.toValue = CATransform3DIdentity
                animation.duration = 0.24
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(animation, forKey: "expandPanelSettings")
            }
        }
    }

    private func presentPanelSettings(_ view: PanelView, menu: PanelMenuModel,
                                      notion: NotionTasksModel?, settings: AnyView?) -> Bool {
        guard state == .pinned, dialog == nil, views[view.id] === view else { return false }
        let hasClockSettings = WidgetSpec(url: view.url)?.kind == .clock
        let settings = documentStorage.noteURL(for: view.url) == nil ? settings : AnyView(
            VStack(alignment: .leading, spacing: 8) {
                PanelTextSizePicker(content: .notes, store: store)
                Text("すべてのメモに適用されます。").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        )
        let size = NSSize(width: 640, height: notion != nil || settings != nil || hasClockSettings ? 540 : 400)
        panelWithSettings = view
        presentDialog(PanelMenuFace(model: menu, settings: settings, notion: notion, showsActions: editing, store: store),
                      size: size, expandingFrom: root.convert(view.bounds, from: view))
        return true
    }
    func presentSettings(_ controller: SettingsController) {
        closeDialog()
        embeddedSettings = controller
        controller.embeddedWindow = panel
        presentDialog(OverlaySettingsForm(controller: controller) { [weak self] in self?.closeDialog() }, size: NSSize(width: 650, height: 560))
        controller.refresh()
    }
    private func performAction(_ action: OverlayAction) {
        closeDialog()
        switch action {
        case .edit: setEditing(!editing)
        case .settings: onOpenSettings?()
        case .quit: NSApp.terminate(nil)
        }
    }
    var onOpenSettings: (() -> Void)?
    var isSettingsKey: (() -> Bool)?
    private var visibilityRevision = 0
    private var monitor: Any?
    private let displayIdentity = DisplayIdentity()
    private var activeDisplay: String?
    private var presentedPage: Int?
    private var activeShared = true
    private var presentationWasFitted = false
    private var ephemeralLayouts: [String: DisplayLayout] = [:]
    private var outsideClickMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private func monitorOutsideInteraction(_ visible: Bool) {
        if !visible {
            if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
            outsideClickMonitor = nil
            for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            workspaceObservers.removeAll()
            return
        }
        guard workspaceObservers.isEmpty else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.state != .hidden, self.panel.attachedSheet == nil else { return }
            self.onDismiss?()
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.state != .hidden,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.onDismiss?()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.state != .hidden else { return }
            self.onDismiss?()
        })
    }

    private var screenObserver: NSObjectProtocol?
    init(store: SettingsStore, websiteDataStore: WKWebsiteDataStore = .default(), documentStorage: PanelDocumentStorage = PanelDocumentStorage(), weatherProvider: any WeatherProviding = WeatherService.shared) {
        self.weatherProvider = weatherProvider
        self.documentStorage = documentStorage
        notes = PanelNotes(files: documentStorage)
        self.websiteDataStore = websiteDataStore
        self.store = store
        usesDoubleEscape = store.doubleEscapeToDismiss
        records = Array(store.panels.prefix(PanelPool.maximum)).map { record in
            var clean = record; clean.url = WebPanelPolicy.launchURL(record.url); return clean
        }
        root = Backdrop(frame: NSRect(x: 0, y: 0, width: 1800, height: 1169))
        panel = OverlayPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.sharingType = store.hideFromScreenCapture ? .none : .readOnly
        panel.contentView = root; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.alphaValue = 0; panel.ignoresMouseEvents = true
        root.dismiss = { [weak self] in self?.onDismiss?() }
        root.addSubview(toolbar)
        pill.alignment = .center; pill.textColor = .secondaryLabelColor
        pill.font = .systemFont(ofSize: 11); toolbar.addSubview(pill)
        addButton = ActionButton("パネルを追加") { [weak self] in self?.addPrompt() }
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading; addButton.contentTintColor = .labelColor
        toolbar.addSubview(addButton)
        editButton = ActionButton("レイアウトを編集") { [weak self] in
            guard let self else { return }; self.setEditing(!self.editing)
        }; editButton.imagePosition = .imageLeading; editButton.contentTintColor = .labelColor
        toolbar.addSubview(editButton)
        for button in [addButton!, editButton!] {
            if #available(macOS 26.0, *) { button.bezelStyle = .glass }
            button.controlSize = .large
            button.font = .systemFont(ofSize: 14, weight: .medium)
        }
        for record in records { install(record); if WidgetSpec(url: record.url) == nil { pool.add(record.id) } }
        reconcile()
        accentObservation = ScrimTheme.shared.$settings.dropFirst().sink { [weak self] _ in
            self?.views.values.forEach { $0.updateAccent() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            let ids = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
            self?.displayIdentity.forgetUnavailable(connected: ids)
        }
        memoryPressure.setEventHandler { [weak self] in
            self?.evictAllParked()
            if self?.state == .hidden { self?.releaseWebPanels(force: true) }
        }
        memoryPressure.resume()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.type == .scrollWheel, self.pagesScroll(event) { return nil }
            if self.state == .peek && self.store.peekAllowsInteraction { return PanelPointerEvents.withoutCommand(event) }
            guard self.state == .pinned else { return event }
            let isEscape = event.type == .keyDown && event.keyCode == 53
                && event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
            if !isEscape { self.lastEscape = nil }
            if event.type == .keyDown, let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                self.lastEscape = nil
                return event
            }
            if self.embeddedSettings?.recordingAnyKeys == true {
                self.lastEscape = nil
                return event
            }
            if event.type == .keyDown && event.charactersIgnoringModifiers == "," &&
                event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command {
                if !event.isARepeat {
                    if self.dialog != nil { self.closeDialog() }
                    else {
                        self.actionSelection.selected = .edit
                        self.presentDialog(OverlayActionList(selection: self.actionSelection, editing: self.editing) { [weak self] in self?.performAction($0) }, size: NSSize(width: 360, height: 206))
                    }
                }
                return nil
            }
            if self.dialog != nil {
                if event.type == .keyDown {
                    switch event.keyCode {
                    case 53:
                        self.lastEscape = nil
                        if !event.isARepeat { self.closeDialog() }
                        return nil
                    case 125, 126:
                        if self.showingActions { self.actionSelection.move(event.keyCode == 125 ? 1 : -1); return nil }
                    case 36, 76:
                        if self.showingActions && !event.isARepeat { self.performAction(self.actionSelection.selected); return nil }
                    default: break
                    }
                }
                return event
            }
            if event.type == .keyDown, self.store.pageCount > 1, [123, 124].contains(event.keyCode),
               self.panel.attachedSheet == nil {
                let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
                if flags == NSEvent.ModifierFlags(rawValue: self.store.pageArrowModifiers) &&
                    !(flags.isEmpty && self.panel.firstResponder is NoteTextView) {
                    if !event.isARepeat { self.selectPage(self.store.currentPage + (event.keyCode == 124 ? 1 : -1)) }
                    return nil
                }
            }
            if event.type == .keyDown && event.keyCode == 14 &&
                event.modifierFlags.intersection([.command, .shift, .control, .option]) == [.command, .shift] {
                if !event.isARepeat { self.setEditing(!self.editing) }
                return nil
            }
            if isEscape, self.panel.attachedSheet == nil {
                guard !event.isARepeat else { return nil }
                if self.editing {
                    self.setEditing(false)
                    return nil
                }
                if self.taskPanelForEscape()?.handleTaskDetailEscape() == true {
                    self.lastEscape = nil
                    return nil
                }
                let doubleEscape = self.store.doubleEscapeToDismiss
                if doubleEscape != self.usesDoubleEscape {
                    self.usesDoubleEscape = doubleEscape
                    self.lastEscape = nil
                }
                if !doubleEscape || self.lastEscape.map({ (0...0.5).contains(event.timestamp - $0) }) == true {
                    self.lastEscape = nil
                    self.onDismiss?()
                    return nil
                }
                self.lastEscape = event.timestamp
                return event
            }
            if event.type == .leftMouseDown {
                let p = self.root.convert(event.locationInWindow, from: nil)
                let view = self.root.subviews.reversed().compactMap { $0 as? PanelView }.first { $0.frame.contains(p) }
                self.clickedPanelID = view?.id
                if let view { self.touch(view.id) }
            }
            return event
        }
    }
    private func taskPanelForEscape() -> PanelView? {
        if let clickedPanelID, let view = views[clickedPanelID] { return view }
        var responder = panel.firstResponder
        while let view = responder as? NSView {
            if let card = view as? PanelView { return card }
            responder = view.superview
        }
        return nil
    }
    private func displayKey(for screen: NSScreen) -> String {
        // No screen index/name fallback: missing UUID/number never borrows another display's layout.
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return number.map { displayIdentity.key(for: $0) } ?? "ephemeral:" + UUID().uuidString
    }
    /// The pointer's display, unless the overlay is turned off there. Explicit menu actions
    /// fall back to another enabled display so Settings always stays reachable.
    private func presentationScreen(explicit: Bool) -> (screen: NSScreen, key: String)? {
        guard let pointer = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return nil }
        let pointerKey = displayKey(for: pointer)
        if store.showsOverlay(on: pointerKey) { return (pointer, pointerKey) }
        guard explicit else { return nil }
        let candidates = ([NSScreen.main].compactMap { $0 } + NSScreen.screens).map { ($0, displayKey(for: $0)) }
        return candidates.first { store.showsOverlay(on: $0.1) } ?? (pointer, pointerKey)
    }
    /// Returns false, leaving the overlay hidden, when the pointer's display has the overlay turned off.
    @discardableResult func show(_ next: OverlayState, immediately: Bool = false, explicit: Bool = false) -> Bool {
        let wasHidden = state == .hidden
        var target: (screen: NSScreen, key: String)?
        if wasHidden && next != .hidden {
            target = presentationScreen(explicit: explicit)
            if target == nil { return false }
        }
        if state != next {
            lastEscape = nil
            clickedPanelID = nil
        }
        state = next
        if next == .hidden { scheduleIdleRelease() } else { idleRelease?.invalidate(); idleRelease = nil }
        monitorOutsideInteraction(next != .hidden)
        if next != .pinned { closeDialog(); setEditing(false) }
        visibilityRevision += 1
        let revision = visibilityRevision
        let plan = VisibilityPlan(state: next, peekAllowsInteraction: store.peekAllowsInteraction)
        panel.sharingType = store.hideFromScreenCapture ? .none : .readOnly
        for view in views.values { view.browser.hideFromScreenCapture = store.hideFromScreenCapture; view.setWeatherShowsHourly(store.weatherShowsHourly) }
        panel.ignoresMouseEvents = plan.ignoresMouseEvents
        for view in views.values { view.applyVisibility(plan) }
        layoutChrome()
        if next == .hidden {
            notes.saveAll()
            if immediately {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0; self.panel.animator().alphaValue = 0
                }
                return true
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = plan.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().alphaValue = plan.alpha
            }, completionHandler: { [weak self] in
                guard let self, self.visibilityRevision == revision, self.state == .hidden,
                      self.panel.isKeyWindow, !(self.isSettingsKey?() ?? false) else { return }
                NSApp.deactivate()
            })
            return true
        }
        if wasHidden, let (screen, key) = target {
            // AppKit screen coordinates start at the bottom. Reserve the full notch strip.
            var canvas = screen.frame
            canvas.size.height -= screen.safeAreaInsets.top
            // In-memory arrangements belong to the mode they were made in.
            if activeShared != store.sameLayoutOnAllDisplays { ephemeralLayouts.removeAll() }
            let transient = store.sameLayoutOnAllDisplays ? nil : ephemeralLayouts[ephemeralKey(key)]
            let layout = store.layout(for: key, screen: canvas.size, transient: transient)
            activeDisplay = key; activeShared = store.sameLayoutOnAllDisplays
            panel.setFrame(canvas, display: false); root.frame.size = canvas.size
            loadPageLayout(layout)
            presentedPage = store.currentPage
        }
        if wasHidden { for view in views.values { view.prepareAgendaPresentation(resetScroll: store.agendaResetsScrollOnOpen) } }
        if wasHidden && store.calendarReturnsToToday { for view in views.values { view.returnCalendarToToday() } }
        layoutChrome(); panel.orderFrontRegardless()
        if wasHidden || immediately {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = immediately ? 0 : plan.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().alphaValue = plan.alpha
            }
        }
        if plan.makeKey { panel.makeKey() }
        return true
    }
    private func loadPageLayout(_ layout: DisplayLayout) {
        let selected = Array(layout.panels.prefix(PanelPool.maximum))
        for id in Array(views.keys) where !selected.contains(where: { $0.id == id }) {
            views.removeValue(forKey: id)?.removeFromSuperview(); pool.remove(id)
        }
        records = selected.map { record in
            var clean = record; clean.url = WebPanelPolicy.launchURL(record.url); return clean
        }
        let selectedLayout = DisplayLayout(panels: records, referenceSize: layout.referenceSize)
        presentationWasFitted = !store.sameLayoutOnAllDisplays && LayoutFitter.needsFitting(layout: selectedLayout, screen: root.bounds.size)
        for record in records {
            if views[record.id]?.url != record.url { views.removeValue(forKey: record.id)?.removeFromSuperview(); pool.remove(record.id) }
            if views[record.id] == nil { install(record); if WidgetSpec(url: record.url) == nil { pool.add(record.id) } }
            views[record.id]?.setWebDisplayMode(record.webDisplayMode ?? store.webDisplayMode)
        }
        for (record, frame) in zip(records, presentationFrames(layout: DisplayLayout(panels: records, referenceSize: layout.referenceSize), screen: root.bounds.size)) {
            views[record.id]?.frame = frame
            if let view = views[record.id] { root.addSubview(view, positioned: .above, relativeTo: nil); view.needsLayout = true }
        }
        reconcile()
    }
    private struct ParkedCanvas {
        var index: Int
        let pool: PanelPool
        let views: [UUID: PanelView]
        let addresses: [UUID: URL]
    }
    private var parkedCanvases: [ParkedCanvas] = []
    /// Parked pages hold live web views outside the window; dropping one must free their pages too.
    private func evict(_ canvas: ParkedCanvas) { canvas.views.values.forEach { $0.discardWeb() } }
    private func evictAllParked() { parkedCanvases.forEach(evict); parkedCanvases.removeAll() }
    /// Web pages are the largest memory cost (one WebKit content process each, often 100–400 MB).
    /// After the overlay stays hidden this long, they are swapped for snapshots; the next show reloads them.
    static let idleReleaseDelay: TimeInterval = 10 * 60
    private var idleRelease: Timer?
    private func scheduleIdleRelease() {
        idleRelease?.invalidate(); idleRelease = nil
        guard store.releasesIdleWebPanels else { return }
        idleRelease = Timer.scheduledTimer(withTimeInterval: Self.idleReleaseDelay, repeats: false) { [weak self] _ in
            self?.releaseWebPanels(force: false)
        }
    }
    /// Snapshots and releases every web page while hidden (parked pages too). Logins in progress are kept.
    func releaseWebPanels(force: Bool) {
        guard state == .hidden, force || store.releasesIdleWebPanels else { return }
        evictAllParked()
        for view in views.values where view.web != nil { view.releaseWeb() }
    }
    private let memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)

    private func exchangeWebSessions(for index: Int, layout: DisplayLayout, outgoingIndex: Int) {
        let incoming = parkedCanvases.firstIndex { $0.index == index }.map { parkedCanvases.remove(at: $0) }
        let live = views.filter { $0.value.web != nil }
        if !live.isEmpty {
            for view in live.values {
                view.applyVisibility(VisibilityPlan(state: .hidden))
                view.removeFromSuperview()
            }
            let addresses = live.mapValues { $0.url }
            parkedCanvases.append(ParkedCanvas(index: outgoingIndex, pool: pool, views: live, addresses: addresses))
            // One parked page keeps back-and-forth switching instant without holding several pages of web processes.
            if parkedCanvases.count > 1 { evict(parkedCanvases.removeFirst()) }
        }
        for view in views.values where view.superview != nil { view.removeFromSuperview() }
        views.removeAll()
        pool = incoming?.pool ?? PanelPool()
        let selected = Set(layout.panels.map(\.id))
        for entry in pool.entries where !selected.contains(entry.id) { pool.remove(entry.id) }
        guard let incoming else { return }
        for record in layout.panels {
            guard let view = incoming.views[record.id], incoming.addresses[record.id] == WebPanelPolicy.launchURL(record.url) else { continue }
            views[record.id] = view
            view.browser.hideFromScreenCapture = store.hideFromScreenCapture
            view.setEditing(editing)
            view.applyVisibility(VisibilityPlan(state: state, peekAllowsInteraction: store.peekAllowsInteraction))
        }
    }
    private let pageBar = NSStackView()
    private var pageBarState = ""
    private var swipeDistance: CGFloat = 0
    private var verticalDistance: CGFloat = 0
    private var pagingGesture = false
    private var verticalGesture = false

    func selectPage(_ index: Int) {
        guard state == .pinned, dialog == nil, panel.attachedSheet == nil,
              (0..<store.pageCount).contains(index), index != store.currentPage, let key = activeDisplay else { return }
        lastEscape = nil
        clickedPanelID = nil
        persist()
        placementPreview = nil
        let outgoingIndex = store.currentPage
        store.currentPage = index
        let transient = store.sameLayoutOnAllDisplays ? nil : ephemeralLayouts[ephemeralKey(key)]
        var layout = store.layout(for: key, screen: root.bounds.size, transient: transient)
        exchangeWebSessions(for: index, layout: layout, outgoingIndex: outgoingIndex)
        // A background login redirect may have completed while this canvas was parked.
        for i in layout.panels.indices {
            if let view = views[layout.panels[i].id] { layout.panels[i].url = view.url }
        }
        loadPageLayout(layout)
        presentedPage = index
        for view in views.values { view.prepareAgendaPresentation(resetScroll: store.agendaResetsScrollOnOpen) }
        layoutChrome()
        NotificationCenter.default.post(name: .meetingBadgeChanged, object: nil)
    }

    private func ephemeralKey(_ display: String) -> String { "\(store.currentPage).\(display)" }

    private func pagesScroll(_ event: NSEvent) -> Bool {
        guard state == .pinned, dialog == nil, panel.attachedSheet == nil, store.pageCount > 1,
              event.hasPreciseScrollingDeltas else { return false }
        if !event.momentumPhase.isEmpty { return pagingGesture }
        if event.phase == .began {
            swipeDistance = 0; verticalDistance = 0; pagingGesture = false; verticalGesture = false
        }
        guard !event.phase.isEmpty else { return false }
        swipeDistance += event.scrollingDeltaX
        verticalDistance += event.scrollingDeltaY
        if !pagingGesture && !verticalGesture {
            if abs(swipeDistance) > 8 && abs(swipeDistance) > abs(verticalDistance) * 1.5 { pagingGesture = true }
            else if abs(verticalDistance) > 8 { verticalGesture = true }
        }
        guard pagingGesture else { return false }
        let threshold = min(110, root.bounds.width * 0.12)
        if event.phase == .ended && abs(swipeDistance) >= threshold * 0.55 {
            selectPage(store.currentPage + (swipeDistance < 0 ? 1 : -1))
        }
        return true
    }

    private func confirmPageRemoval() {
        guard editing, store.pageCount > 1, panel.attachedSheet == nil else { return }
        let index = store.currentPage
        let alert = NSAlert()
        alert.messageText = "ページ " + String(index + 1) + " を削除しますか？"
        alert.informativeText = "このページに配置したパネルを、すべてのディスプレイのレイアウトから取り除きます。Webページや元のファイルは保持されます。"
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "削除").hasDestructiveAction = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            DispatchQueue.main.async { self?.removeCurrentPage(index) }
        }
    }

    func removeCurrentPage(_ index: Int) {
        guard editing, index == store.currentPage, store.pageCount > 1 else { return }
        let neighbor = index == 0 ? 1 : index - 1
        selectPage(neighbor)
        guard store.currentPage == neighbor else { return }
        store.removePage(index)
        presentedPage = store.currentPage
        parkedCanvases.filter { $0.index == index }.forEach(evict)
        parkedCanvases.removeAll { $0.index == index }
        for i in parkedCanvases.indices where parkedCanvases[i].index > index { parkedCanvases[i].index -= 1 }
        var remaining: [String: DisplayLayout] = [:]
        for (key, layout) in ephemeralLayouts {
            let parts = key.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let page = Int(parts[0]), page != index else { continue }
            remaining["\(page > index ? page - 1 : page).\(parts[1])"] = layout
        }
        ephemeralLayouts = remaining
        layoutChrome()
        NotificationCenter.default.post(name: .meetingBadgeChanged, object: nil)
    }

    func movePage(_ source: Int, to destination: Int) {
        guard editing, dialog == nil, panel.attachedSheet == nil, source != destination,
              (0..<store.pageCount).contains(source), (0..<store.pageCount).contains(destination) else { return }
        persist()
        let order = store.movePage(source, to: destination)
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        for i in parkedCanvases.indices {
            if let position = positions[parkedCanvases[i].index] { parkedCanvases[i].index = position }
        }
        var remapped: [String: DisplayLayout] = [:]
        for (key, layout) in ephemeralLayouts {
            let parts = key.split(separator: ".", maxSplits: 1)
            if parts.count == 2, let old = Int(parts[0]), let position = positions[old] {
                remapped["\(position).\(parts[1])"] = layout
            }
        }
        ephemeralLayouts = remapped
        presentedPage = store.currentPage
        layoutChrome()
    }

    private func pageActions(_ dot: EditablePageDot) {
        let page = dot.page
        let menu = NSMenu()
        menu.addItem(withTitle: "ページ \(page + 1)" + (page == store.currentPage ? "（表示中）" : ""), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.tag = page
            item.target = self
        }
        if page != store.currentPage { add("このページを開く", #selector(openPageItem(_:))) }
        if page > 0 { add("左へ移動", #selector(movePageLeft(_:))) }
        if page + 1 < store.pageCount { add("右へ移動", #selector(movePageRight(_:))) }
        if store.pageCount > 1 {
            menu.addItem(.separator())
            add("ページ \(page + 1) 全体を削除…", #selector(removePageItem(_:)))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: dot.bounds.maxY + 4), in: dot)
    }
    @objc private func openPageItem(_ item: NSMenuItem) { selectPage(item.tag) }
    @objc private func movePageLeft(_ item: NSMenuItem) { movePage(item.tag, to: item.tag - 1) }
    @objc private func movePageRight(_ item: NSMenuItem) { movePage(item.tag, to: item.tag + 1) }
    @objc private func removePageItem(_ item: NSMenuItem) {
        selectPage(item.tag)
        if store.currentPage == item.tag { confirmPageRemoval() }
    }

    private func layoutPageBar() {
        let count = store.pageCount, index = store.currentPage
        pageBar.isHidden = state == .hidden || (count == 1 && !editing)
        guard !pageBar.isHidden else { return }
        let signature = "\(index)/\(count)/\(editing)"
        if signature != pageBarState {
            pageBarState = signature
            for view in pageBar.arrangedSubviews { pageBar.removeArrangedSubview(view); view.removeFromSuperview() }
            pageBar.orientation = .horizontal; pageBar.spacing = 0
            pageBar.edgeInsets = NSEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
            pageBar.wantsLayer = true; pageBar.layer?.cornerRadius = 12
            pageBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
            let start = max(0, min(index - 4, count - 9))
            for page in start..<min(count, start + 9) {
                if editing {
                    let dot = EditablePageDot(page: page, selected: page == index)
                    dot.move = { [weak self] source, destination in self?.movePage(source, to: destination) }
                    dot.openMenu = { [weak self] dot in self?.pageActions(dot) }
                    dot.widthAnchor.constraint(equalToConstant: 28).isActive = true
                    pageBar.addArrangedSubview(dot)
                    continue
                }
                let button = ActionButton(page == index ? "●" : "○") { [weak self] in self?.selectPage(page) }
                button.isBordered = false; button.contentTintColor = .white
                button.setAccessibilityLabel("ページ \(page + 1) / \(count)")
                button.toolTip = "ページ \(page + 1) / \(count)"
                button.widthAnchor.constraint(equalToConstant: 22).isActive = true
                pageBar.addArrangedSubview(button)
            }
            if editing {
                let add = ActionButton("＋") { [weak self] in
                    guard let self, self.editing else { return }
                    self.selectPage(self.store.appendPage())
                }
                add.isBordered = false; add.contentTintColor = .white; add.toolTip = "ページを追加"
                add.setAccessibilityLabel("ページを追加"); pageBar.addArrangedSubview(add)
            }
        }
        let size = pageBar.fittingSize
        pageBar.frame = CGRect(x: root.bounds.midX - size.width/2, y: editing ? 106 : 4, width: size.width, height: max(24, size.height))
        root.addSubview(pageBar, positioned: dialog == nil ? .above : .below, relativeTo: dialog)
    }

    func layoutChrome() {
        layoutPageBar()
        let width: CGFloat = 432
        toolbar.frame = NSRect(x: root.bounds.midX-width/2, y: 24, width: width, height: editing ? 80 : 56)
        toolbar.isHidden = state != .pinned || !editing
        addButton.title = records.isEmpty ? "最初のパネルを追加" : "パネルを追加"
        addButton.frame = NSRect(x: 8, y: 30, width: 256, height: 44); addButton.isHidden = !editing
        editButton.toolTip = "レイアウト編集を切り替え（⌘⇧E）"
        editButton.title = editing ? "完了" : "レイアウトを編集"
        editButton.image = NSImage(systemSymbolName: editing ? "checkmark" : "square.and.pencil", accessibilityDescription: nil)
        editButton.frame = editing ? NSRect(x: 280, y: 30, width: 144, height: 44) : NSRect(x: 0, y: 6, width: 224, height: 44)
        pill.stringValue = "ドラッグで移動 · 端でサイズ変更 · Esc で完了"
        pill.frame = NSRect(x: 16, y: 8, width: 400, height: 18); pill.isHidden = !editing
        root.addSubview(toolbar, positioned: dialog == nil ? .above : .below, relativeTo: dialog)
    }
    func setEditing(_ value: Bool) {
        lastEscape = nil
        closeDialog()
        editing = value && state == .pinned
        panel.acceptsMouseMovedEvents = editing
        if !editing { placementPreview = nil }
        root.editing = editing
        for view in views.values {
            view.setEditing(editing)
        }
        layoutChrome()
    }
    private var placementPreview: (id: UUID, originals: [UUID: CGRect], last: CGRect?)?

    private func previewPlacement(_ id: UUID, target: CGRect) -> CGRect {
        if placementPreview?.id != id {
            placementPreview = (id, views.mapValues { $0.frame }, nil)
        }
        let packing = PanelPacking(screen: root.bounds.size)
        let snapped = packing.snapped(target)
        if placementPreview?.last == snapped { return snapped }
        let ids = records.map(\.id).filter { $0 != id }
        guard let original = placementPreview?.originals,
              ids.allSatisfy({ original[$0] != nil }),
              let fit = packing.layout(target: snapped, others: ids.compactMap { original[$0] }) else {
            return placementPreview?.last ?? views[id]?.frame ?? target
        }
        for (other, frame) in zip(ids, fit.others) where views[other]?.frame != frame {
            views[other]?.settleFrame(frame)
        }
        placementPreview?.last = fit.target
        return fit.target
    }

    private func install(_ record: PanelRecord) {
        let view = PanelView(record: record, websiteDataStore: websiteDataStore, fileReadAccessRoot: documentStorage.resourceRoot(for: record.url), weatherProvider: weatherProvider, notes: notes); views[record.id] = view; root.addSubview(view)
        view.browser.hideFromScreenCapture = store.hideFromScreenCapture
        view.setWeatherShowsHourly(store.weatherShowsHourly)
        view.setWebDisplayMode(record.webDisplayMode ?? store.webDisplayMode)
        view.applyVisibility(VisibilityPlan(state: state, peekAllowsInteraction: store.peekAllowsInteraction))
        view.setEditing(editing)
        if case .html = view.fileState.source {
            view.canEditContent = documentStorage.owns(record.url)
        } else { view.canEditContent = documentStorage.noteURL(for: record.url) != nil }
        view.frame = record.placement.restore(screen: root.bounds.size)
        view.touched = { [weak self] in self?.touch(record.id) }
        view.changed = { [weak self] in self?.placementPreview = nil; self?.saveFrames() }
        view.didOpenWebLink = { [weak self] in self?.onDismiss?() }
        view.didSleep = { [weak self] in self?.reconcile() }
        view.navigated = { [weak self] url in
            guard let self, let index = self.records.firstIndex(where: { $0.id == record.id }) else { return }
            self.records[index].url = url; self.persist()
        }
        view.constrain = { [weak self] frame in self?.previewPlacement(record.id, target: frame) ?? frame }
        view.presentSettings = { [weak self] view, menu, notion, settings in
            self?.presentPanelSettings(view, menu: menu, notion: notion, settings: settings) ?? false
        }
        view.dismissSettings = { [weak self, weak view] in
            guard let self, self.panelWithSettings === view else { return }
            self.closeDialog()
        }
        view.saveWebSettings = { [weak self] url, mode in
            self?.closeDialog()
            self?.updateWebPanel(record.id, url: url, mode: mode)
        }
        view.command = { [weak self] command in
            guard let self, self.editing, let view = self.views[record.id] else { return }
            switch command {
            case 0: self.touch(record.id); view.reloadContent()
            case 1: view.openExternally(view.web?.url ?? self.documentStorage.contentURL(for: view.url))
            case 2:
                let mode = self.records.first(where: { $0.id == record.id })?.webDisplayMode ?? self.store.webDisplayMode
                self.add(view.web?.url ?? view.url, mode: mode)
            case 4:
                guard self.documentStorage.owns(view.url) else { return }
                if self.documentStorage.noteURL(for: view.url) != nil {
                    self.editNote(view)
                } else if case .html = view.fileState.source { self.htmlPrompt(existing: view) }
            case 27:
                guard case .text(let file) = view.fileState.source else { return }
                do { self.addNote(try PanelDocumentStorage.readText(at: file)) }
                catch { NSAlert(error: error).beginSheetModal(for: self.panel) }
            default: view.discardWeb(); view.removeFromSuperview(); self.views.removeValue(forKey: record.id); PanelActions.close(record.id, records: &self.records, pool: &self.pool); self.persist(); self.layoutChrome()
            }
        }
    }
    func updateWebPanel(_ id: UUID, url: URL, mode: WebDisplayMode) {
        guard editing, let index = records.firstIndex(where: { $0.id == id }), let view = views[id],
              ["http", "https"].contains(view.url.scheme?.lowercased()), EventLinks.isWebURL(url) else { return }
        records[index].webDisplayMode = mode
        if records[index].url != url {
            let frame = view.frame
            view.navigated = nil
            view.discardWeb()
            view.removeFromSuperview()
            records[index].url = url
            install(records[index])
            views[id]?.frame = frame
            reconcile()
            layoutChrome()
        } else {
            view.setWebDisplayMode(mode)
        }
        persist()
    }

    private func reconcile() {
        // Native widgets are cheap views, not part of the four-WebView limit.
        for view in views.values where WidgetSpec(url: view.url) != nil { view.wake() }
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
        layoutChrome()
        if editing, let index = records.firstIndex(where: { $0.id == id }) {
            let record = records.remove(at: index); records.append(record); persist()
        }
    }
    func add(_ url: URL, at target: CGRect? = nil, mode: WebDisplayMode = .desktop) {
        guard editing else { return }
        guard records.count < PanelPool.maximum else { NSSound.beep(); return }
        let originals = views.mapValues { $0.frame }
        let frame = target ?? PanelPacking(screen: root.bounds.size).initial(others: Array(originals.values))
        let record = PanelRecord(url: url, placement: FractionalFrame(frame: frame, screen: root.bounds.size), webDisplayMode: ["https", "http"].contains(url.scheme?.lowercased()) ? mode : nil)
        records.append(record); install(record); if WidgetSpec(url: record.url) == nil { pool.add(record.id) }
        placementPreview = (record.id, originals, nil)
        let placed = previewPlacement(record.id, target: frame)
        views[record.id]?.frame = placed
        reconcile(); persist(); layoutChrome()
    }
    private func addPrompt() {
        guard editing else { return }
        guard records.count < PanelPool.maximum else { NSSound.beep(); return }
        closeDialog()
        showingGallery = true
        presentDialog(PanelGallery(choose: { [weak self] tag in
            guard let self, self.showingGallery, self.galleryDrag == nil else { return }
            self.closeDialog()
            self.addSource(tag)
        }, drag: { [weak self] tag, ended in self?.dragGalleryCard(tag, ended: ended) }, close: { [weak self] in self?.closeDialog() }), size: NSSize(width: 850, height: 680))
    }
    private func dragGalleryCard(_ tag: Int, ended: Bool) {
        guard editing, showingGallery, let dialog else { return }
        if galleryDrag == nil {
            let marker = NSView()
            marker.wantsLayer = true
            marker.layer?.cornerRadius = 12
            marker.layer?.borderWidth = 2
            marker.layer?.borderColor = ScrimTheme.shared.accent.nativeInk.cgColor
            marker.layer?.backgroundColor = ScrimTheme.shared.accent.nativeInk.withAlphaComponent(0.2).cgColor
            root.addSubview(marker, positioned: .below, relativeTo: dialog)
            galleryDrag = (views.mapValues { $0.frame }, marker)
            dialog.alphaValue = 0
        }
        guard let drag = galleryDrag else { return }
        let point = root.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard root.bounds.contains(point) else {
            drag.marker.isHidden = true
            if ended { clearGalleryDrag() }
            return
        }
        drag.marker.isHidden = false
        let grid = PanelGrid(screen: root.bounds.size)
        var target = grid.frame(column: 0, row: 0, columns: 2, rows: 1)
        target.origin = CGPoint(x: point.x-target.width/2, y: point.y-target.height/2)
        let ids = records.map(\.id)
        let packing = PanelPacking(screen: root.bounds.size)
        if !ended, drag.marker.frame == packing.snapped(target) { return }
        guard let fit = packing.layout(target: target, others: ids.compactMap { drag.originals[$0] }) else { clearGalleryDrag(); return }
        if ended {
            closeDialog()
            addSource(tag, at: fit.target)
        } else {
            if drag.marker.frame.isEmpty { drag.marker.frame = fit.target } else { drag.marker.settleFrame(fit.target) }
            for (id, frame) in zip(ids, fit.others) { views[id]?.settleFrame(frame) }
        }
    }

    private func addSource(_ tag: Int, at target: CGRect? = nil) {
        guard editing else { return }
        switch tag {
        case 1: addNote(at: target)
        case 2: htmlPrompt(at: target)
        case 5: addNotionViewPrompt(at: target)
        case 4: importHTMLPrompt(at: target)
        case 10: add(WidgetSpec(kind: .weather).url, at: target)
        case 11: add(WidgetSpec(kind: .clock).url, at: target)
        case 12: add(WidgetSpec(kind: .calendar).url, at: target)
        case 15: add(WidgetSpec(kind: .calculator).url, at: target)
        case 14: add(WidgetSpec(kind: .worldclock).url, at: target)
        case 13: add(WidgetSpec(kind: .upcoming).url, at: target)
        case 16: add(WidgetSpec(kind: .notionTasks).url, at: target)
        case 3:
            let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = true
            picker.allowedContentTypes = [.pdf, .html, .plainText, .rtf, UTType(filenameExtension: "md") ?? .plainText,
                                          UTType(filenameExtension: "log") ?? .plainText, UTType(filenameExtension: "xhtml") ?? .html]
            picker.beginSheetModal(for: panel) { [weak self] response in
                if response == .OK { for (i, url) in picker.urls.enumerated() { self?.add(url, at: i == 0 ? target : nil) } }
            }
        default: addWebPrompt(at: target)
        }
    }
    private func addNotionViewPrompt(_ previous: String = "", invalid: Bool = false, at target: CGRect? = nil) {
        let alert = NSAlert()
        alert.messageText = "Notionデータベースのビューを追加"
        alert.informativeText = invalid ? "ビューを特定できません。Notionのビュー名のメニューから「ビューのリンクをコピー」して貼り付けてください。" : "Notionで表示したいビューのリンクをコピーして貼り付けてください。"
        alert.addButton(withTitle: "追加")
        alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = previous
        field.placeholderString = "https://www.notion.so/…?v=…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            if let url = WebPanelPolicy.notionViewURL(field.stringValue) { self?.add(url, at: target) }
            else { DispatchQueue.main.async { self?.addNotionViewPrompt(field.stringValue, invalid: true, at: target) } }
        }
    }
    private func addWebPrompt(at target: CGRect?) {
        let alert = NSAlert(); alert.messageText = "ウェブパネルを追加"; alert.addButton(withTitle: "追加"); alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24)); field.placeholderString = "https://example.com"; alert.accessoryView = field
        alert.beginSheetModal(for: panel) { [weak self] response in if response == .alertFirstButtonReturn, let url = SettingsStore.normalize(field.stringValue) { self?.add(url, at: target) } }
    }
    private func importHTMLPrompt(at target: CGRect?) {
        guard editing else { return }
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = true
        picker.allowedContentTypes = [.html, .folder, UTType(filenameExtension: "xhtml") ?? .html]
        picker.prompt = "取り込む"; picker.message = "HTMLをコピーして保存します。画像・CSSを含める場合は、そのフォルダを選んでください。"
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK, let selected = picker.url else { return }
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected.path, isDirectory: &directory), directory.boolValue {
                let index = ["index.html", "index.htm", "index.xhtml"].map { selected.appendingPathComponent($0) }
                    .first { FileManager.default.isReadableFile(atPath: $0.path) }
                if let index { self.importHTML(index, root: selected, at: target) }
                else {
                    let entry = NSOpenPanel(); entry.canChooseDirectories = false; entry.directoryURL = selected
                    entry.allowedContentTypes = [.html, UTType(filenameExtension: "xhtml") ?? .html]
                    entry.message = "このフォルダ内で、最初に表示するHTMLを選んでください。"
                    entry.beginSheetModal(for: self.panel) { [weak self] response in
                        if response == .OK, let file = entry.url { self?.importHTML(file, root: selected, at: target) }
                    }
                }
            } else { self.importHTML(selected, at: target) }
        }
    }
    private func importHTML(_ source: URL, root: URL? = nil, at target: CGRect? = nil) {
        guard editing, records.count < PanelPool.maximum else { return }
        let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        progress.title = "HTMLを取り込み中"; progress.isReleasedWhenClosed = false
        let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 34, width: 28, height: 28)); spinner.style = .spinning
        progress.contentView?.addSubview(spinner); spinner.startAnimation(nil)
        let text = NSTextField(labelWithString: "ファイルをコピーしています…"); text.frame = NSRect(x: 68, y: 36, width: 268, height: 24)
        progress.contentView?.addSubview(text); panel.beginSheet(progress)
        let storage = documentStorage
        Task { @MainActor [weak self] in
            let result = await Task.detached { Result { try storage.importHTML(source, resourceRoot: root) } }.value
            guard let self else { return }
            self.panel.endSheet(progress); progress.close()
            do { let imported = try result.get(); if self.editing { self.add(imported, at: target) } }
            catch { NSAlert(error: error).beginSheetModal(for: self.panel, completionHandler: nil) }
        }
    }
    private func editNote(_ view: PanelView) {
        setEditing(false)
        touch(view.id)
        panel.makeKey()
        view.focusNote()
    }

    func addNote(_ contents: NSAttributedString = NSAttributedString(string: ""), at target: CGRect? = nil) {
        guard editing, records.count < PanelPool.maximum else { return }
        do {
            let url = try documentStorage.createNote(contents)
            add(url, at: target)
            if let id = records.last?.id, let view = views[id] { editNote(view) }
        } catch { NSAlert(error: error).beginSheetModal(for: panel) }
    }

    private func htmlPrompt(existing: PanelView? = nil, at target: CGRect? = nil) {
        guard editing else { return }
        let alert = NSAlert()
        alert.messageText = existing == nil ? "HTML パネルを追加" : "HTML を編集"
        alert.informativeText = "HTML を入力するか、貼り付けてください。"
        alert.addButton(withTitle: existing == nil ? "追加" : "保存"); alert.addButton(withTitle: "キャンセル")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 280)); scroll.hasVerticalScroller = true
        let editor = NSTextView(frame: scroll.bounds); editor.isRichText = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = .width
        editor.textContainer?.widthTracksTextView = true
        if let existing { editor.string = (try? String(contentsOf: existing.url)) ?? "" }
        scroll.documentView = editor; alert.accessoryView = scroll; alert.window.initialFirstResponder = editor
        alert.beginSheetModal(for: panel) { [weak self, weak existing] response in
            guard let self, self.editing, response == .alertFirstButtonReturn else { return }
            do {
                if let existing {
                    try self.documentStorage.replace(editor.string, at: existing.url); existing.reloadContent()
                } else {
                    guard self.records.count < PanelPool.maximum else { NSSound.beep(); return }
                    let url = try self.documentStorage.create(editor.string, kind: .html); self.add(url, at: target)
                }
            } catch { NSAlert(error: error).beginSheetModal(for: self.panel) }
        }
    }
    private func presentationFrames(layout: DisplayLayout, screen: CGSize) -> [CGRect] {
        store.sameLayoutOnAllDisplays ? LayoutFitter.relativeFrames(layout: layout, screen: screen)
                                     : LayoutFitter.frames(layout: layout, screen: screen)
    }
    private func saveFrames() {
        guard editing else { return }
        persist()
    }
    private func displayedLayout() -> DisplayLayout {
        var displayed = records
        for i in displayed.indices {
            if let view = views[displayed[i].id] { displayed[i].placement = FractionalFrame(frame: galleryDrag?.originals[displayed[i].id] ?? view.frame, screen: root.bounds.size) }
        }
        return DisplayLayout(panels: displayed, referenceSize: root.bounds.size)
    }
    private func persist() {
        guard let display = activeDisplay else { return }
        guard presentedPage == store.currentPage else { return }
        let layout = displayedLayout()
        records = layout.panels
        // Web navigation callbacks can arrive after the settings toggle but before show.
        guard activeShared == store.sameLayoutOnAllDisplays else { return }
        // Displays without a UUID keep their arrangement in memory; content is still shared.
        if !activeShared && display.hasPrefix("ephemeral:") { ephemeralLayouts[ephemeralKey(display)] = layout }
        store.savePresentedLayout(layout, for: display, wasFitted: presentationWasFitted)
    }
    deinit {
        memoryPressure.cancel()
        monitorOutsideInteraction(false)
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.orderOut(nil)
    }
}

/// Moves a discarded web view to a blank page under an unrelated origin (never fetched). That load runs in a fresh
/// content process, and WebKit suspends the old process, which returns the page's memory even if AppKit keeps the
/// view object alive. The view leaves its superview once the blank page loads (or after a few seconds).
private final class BlankPageUnloader: NSObject, WKNavigationDelegate {
    static let blankOrigin = URL(string: "https://released.scrim.invalid/")!
    private var view: WKWebView?
    private var keepAlive: BlankPageUnloader?
    static func unload(_ view: WKWebView) {
        let unloader = BlankPageUnloader(view)
        view.navigationDelegate = unloader
        view.loadHTMLString("<!doctype html><title></title>", baseURL: blankOrigin)
    }
    private init(_ view: WKWebView) {
        self.view = view
        super.init()
        keepAlive = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.finish() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish() }
    private func finish() {
        guard let view else { return }
        self.view = nil
        view.navigationDelegate = nil; view.removeFromSuperview()
        keepAlive = nil
    }
}
