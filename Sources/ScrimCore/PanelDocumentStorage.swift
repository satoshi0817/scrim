import Foundation

public enum PanelImportError: LocalizedError {
    case outsideFolder, containsStorage
    public var errorDescription: String? {
        switch self {
        case .outsideFolder: return "選択したフォルダの中にあるHTMLを指定してください。"
        case .containsStorage: return "HTMLと関連ファイルをまとめたフォルダを選択してください。アプリの保存先を含むフォルダは取り込めません。"
        }
    }
}

/// User-authored panel contents are ordinary local files, one directory per panel
/// so an HTML document's file-access grant never includes other panel documents.
public struct PanelDocumentStorage: Sendable {
    public enum Kind: String { case text, html }
    public let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scrim/PanelDocuments", isDirectory: true)
    }
    public func create(_ content: String, kind: Kind) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(kind == .html ? "index.html" : "note.txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    public func owns(_ url: URL) -> Bool {
        url.isFileURL && url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/")
    }
    /// Copy a selected HTML file, or a user-selected resource directory. The
    /// imported document never depends on the original path after this returns.
    public func importHTML(_ source: URL, resourceRoot: URL? = nil) throws -> URL {
        guard case .html = PanelSource.classify(source) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let source = source.resolvingSymlinksInPath()
        let root = resourceRoot?.resolvingSymlinksInPath()
        if let root, !source.path.hasPrefix(root.path+"/") { throw PanelImportError.outsideFolder }
        if let root {
            let storage = directory.resolvingSymlinksInPath().path
            guard storage != root.path && !storage.hasPrefix(root.path+"/") else { throw PanelImportError.containsStorage }
        }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            if let root {
                try copyResources(from: root, to: folder)
                let imported = folder.appendingPathComponent(String(source.path.dropFirst(root.path.count+1)))
                guard FileManager.default.isReadableFile(atPath: imported.path) else { throw CocoaError(.fileReadNoSuchFile) }
                return imported
            }
            let target = folder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: target)
            // Standard browser "Save complete webpage" companion directories.
            for suffix in ["_files", ".files"] {
                let resources = source.deletingLastPathComponent()
                    .appendingPathComponent(source.deletingPathExtension().lastPathComponent+suffix, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: resources.path, isDirectory: &isDirectory), isDirectory.boolValue,
                   try resources.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true {
                    try copyResources(from: resources, to: folder.appendingPathComponent(resources.lastPathComponent, isDirectory: true))
                }
            }
            return target
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    public func resourceRoot(for url: URL) -> URL? {
        guard owns(url) else { return nil }
        let root = directory.resolvingSymlinksInPath()
        let path = String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count+1))
        guard let first = path.split(separator: "/").first else { return nil }
        return root.appendingPathComponent(String(first), isDirectory: true)
    }
    private func copyResources(from source: URL, to target: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files {
            let values = try file.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { continue }
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if values.isDirectory == true { try copyResources(from: file, to: destination) }
            else if values.isRegularFile == true { try FileManager.default.copyItem(at: file, to: destination) }
        }
    }
    public func replace(_ content: String, at url: URL) throws {
        guard owns(url) else { throw CocoaError(.fileWriteNoPermission) }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
