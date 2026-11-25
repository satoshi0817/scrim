import AppKit
import ScrimCore

final class PanelNote: NSObject {
    let url: URL
    let content = NSTextContentStorage()
    let text: NSTextStorage
    let undo = UndoManager()
    fileprivate(set) var saveError: Error?
    static let saveStatusChanged = Notification.Name("ScrimNoteSaveStatusChanged")

    init(url: URL, body: NSAttributedString) {
        self.url = url
        text = NSTextStorage(attributedString: body)
        content.textStorage = text
    }
}

/// Duplicate panels attach separate editors to the same TextKit document.
/// Only unsaved documents need to outlive their last panel.
final class PanelNotes {
    let files: PanelDocumentStorage
    private let openNotes = NSMapTable<NSURL, PanelNote>.strongToWeakObjects()
    private var pending: [URL: PanelNote] = [:]
    private var timer: Timer?

    init(files: PanelDocumentStorage) { self.files = files }

    func open(_ url: URL) throws -> PanelNote {
        guard let destination = files.noteURL(for: url) else { throw CocoaError(.fileWriteNoPermission) }
        if let note = openNotes.object(forKey: destination as NSURL),
           pending[destination] != nil || !note.content.textLayoutManagers.isEmpty { return note }
        let body = try PanelDocumentStorage.readText(at: files.contentURL(for: url))
        let note = PanelNote(url: destination, body: body)
        openNotes.setObject(note, forKey: destination as NSURL)
        return note
    }

    func changed(_ note: PanelNote) {
        pending[note.url] = note
        if let timer {
            timer.fireDate = Date(timeIntervalSinceNow: 0.45)
            return
        }
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in self?.saveAll() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @discardableResult func save(_ note: PanelNote) -> Bool {
        guard pending[note.url] != nil else { return true }
        let wasFailing = note.saveError != nil
        do {
            try files.saveNote(note.text, at: note.url)
            pending.removeValue(forKey: note.url)
            note.saveError = nil
        } catch { note.saveError = error }
        if wasFailing != (note.saveError != nil) {
            NotificationCenter.default.post(name: PanelNote.saveStatusChanged, object: note)
        }
        return note.saveError == nil
    }

    @discardableResult func saveAll() -> Bool {
        timer?.invalidate()
        timer = nil
        for note in Array(pending.values) { save(note) }
        return pending.isEmpty
    }
}
