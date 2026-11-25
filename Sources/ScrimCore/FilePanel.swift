import Foundation
import AppKit

public enum PanelSource: Equatable {
    case web(URL), html(URL), pdf(URL), text(URL), widget(WidgetSpec), unreadable
    public static func classify(_ url: URL) -> Self {
        if let widget = WidgetSpec(url: url) { return .widget(widget) }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return .web(url) }
        guard url.isFileURL else { return .unreadable }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue, FileManager.default.isReadableFile(atPath: url.path) else { return .unreadable }
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf(url)
        case "html", "htm", "xhtml": return .html(url)
        case "txt", "text", "md", "markdown", "log", "rtf": return .text(url)
        case "":
            // Only extensionless files are sniffed; never read beyond the PDF signature.
            do {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let signature = try file.read(upToCount: 5)
                return signature == Data("%PDF-".utf8) ? .pdf(url) : .unreadable
            } catch { return .unreadable }
        default: return .unreadable
        }
    }
}

/// Shared content state. File failures never invoke a dialog presenter.
public struct FilePanelState {
    public static let unreadableMessage = "このファイルは表示できません"
    public enum FailureReason: Equatable { case unsupported, missing, loadFailure }
    public private(set) var failureReason: FailureReason?
    public private(set) var source: PanelSource
    public var reason: String? {
        switch failureReason {
        case .unsupported: return "PDF・HTML・テキストのファイルを開けます。"
        case .missing: return "ファイルが移動または削除された可能性があります。"
        case .loadFailure, nil: return nil
        }
    }
    public var message: String? { source == .unreadable ? Self.unreadableMessage : nil }
    public init(url: URL) {
        source = PanelSource.classify(url)
        if source == .unreadable {
            if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
                failureReason = .missing
            } else if ["pdf", "html", "htm", "xhtml", "txt", "text", "md", "markdown", "log", "rtf"].contains(url.pathExtension.lowercased()) {
                failureReason = .loadFailure
            } else { failureReason = .unsupported }
        }
    }
    public mutating func loadFailed() { source = .unreadable; failureReason = .loadFailure }
}

/// Content-only error surface: it has no window, sheet, or dialog presenter.
public final class FilePanelErrorView: NSView {
    public let messageLabel = NSTextField(labelWithString: FilePanelState.unreadableMessage)
    public let reasonLabel = NSTextField(labelWithString: "")
    public func apply(_ state: FilePanelState) {
        reasonLabel.stringValue = state.reason ?? ""
        reasonLabel.isHidden = state.reason == nil
        needsLayout = true
    }
    public override init(frame: NSRect) {
        super.init(frame: frame)
        messageLabel.alignment = .center
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 14)
        // The panel chrome is dark in both system appearances.
        appearance = NSAppearance(named: .darkAqua)
        reasonLabel.alignment = .center
        reasonLabel.textColor = .secondaryLabelColor
        reasonLabel.font = .systemFont(ofSize: 12)
        reasonLabel.isHidden = true
        addSubview(messageLabel); addSubview(reasonLabel)
    }
    public required init?(coder: NSCoder) { fatalError() }
    public override func layout() {
        super.layout()
        messageLabel.frame = NSRect(x: 0, y: bounds.midY-12, width: bounds.width, height: 24)
        reasonLabel.frame = NSRect(x: 0, y: messageLabel.frame.minY-24, width: bounds.width, height: 20)
    }
}
