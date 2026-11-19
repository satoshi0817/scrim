import AppKit
import WebKit

/// Keep WebKit's supplied configuration: it carries the opener, process pool,
/// and cookie store needed by OAuth popups and window.opener/postMessage.
final class BrowserWindows: NSObject, WKUIDelegate, NSWindowDelegate, WKNavigationDelegate {
    private var windows: [ObjectIdentifier: NSWindow] = [:]
    private var visible = false
    var hideFromScreenCapture = true {
        didSet { for window in windows.values { window.sharingType = hideFromScreenCapture ? .none : .readOnly } }
    }
    var onLastWindowClosed: (() -> Void)?
    var hasOpenWindows: Bool { !windows.isEmpty }
    var popupWebViews: [WKWebView] { windows.values.compactMap { $0.contentView as? WKWebView } }

    func setVisible(_ value: Bool) {
        visible = value
        for window in windows.values {
            if value { window.orderFrontRegardless() } else { window.orderOut(nil) }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self; popup.navigationDelegate = self
        popup.allowsBackForwardNavigationGestures = true
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760),
                             styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.sharingType = hideFromScreenCapture ? .none : .readOnly
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        window.title = "Scrim — ログイン / 新しいウィンドウ"
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = popup; window.delegate = self
        if let screen = webView.window?.screen {
            let area = screen.visibleFrame
            window.setContentSize(NSSize(width: min(640, area.width-40), height: min(760, area.height-80)))
            window.setFrameOrigin(NSPoint(x: area.midX-window.frame.width/2, y: area.midY-window.frame.height/2))
        } else { window.center() }
        windows[ObjectIdentifier(popup)] = window
        if visible { window.makeKeyAndOrderFront(nil) }
        // WebKit performs the original navigation, including POST bodies.
        return popup
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        windows[ObjectIdentifier(webView)]?.title = webView.title ?? "Scrim"
    }
    func webViewDidClose(_ webView: WKWebView) { windows[ObjectIdentifier(webView)]?.close() }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let web = window.contentView as? WKWebView else { return }
        web.stopLoading(); web.uiDelegate = nil; web.navigationDelegate = nil
        windows.removeValue(forKey: ObjectIdentifier(web))
        if windows.isEmpty { onLastWindowClosed?() }
    }
    func closeAll() {
        for window in Array(windows.values) { window.close() }
        windows.removeAll()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        present(message, webView: webView, buttons: ["OK"]) { _, _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        present(message, webView: webView, buttons: ["OK", "キャンセル"]) { response, _ in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        present(prompt, webView: webView, buttons: ["OK", "キャンセル"], input: defaultText ?? "") { response, text in
            completionHandler(response == .alertFirstButtonReturn ? text : nil)
        }
    }
    private func present(_ message: String, webView: WKWebView, buttons: [String], input: String? = nil,
                         completion: @escaping (NSApplication.ModalResponse, String?) -> Void) {
        guard let window = webView.window else { completion(.abort, nil); return }
        let alert = NSAlert(); alert.messageText = webView.url?.host ?? "Scrim"; alert.informativeText = message
        for title in buttons { alert.addButton(withTitle: title) }
        let field = input.map { NSTextField(string: $0) }
        if let field { field.frame = NSRect(x: 0, y: 0, width: 320, height: 24); alert.accessoryView = field }
        alert.beginSheetModal(for: window) { response in completion(response, field?.stringValue) }
    }
}
