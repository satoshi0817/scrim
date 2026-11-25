import AppKit

enum NoteFormat: Int, CaseIterable {
    case bold, underline, bullets, numbers

    var label: String {
        switch self {
        case .bold: return "太字"
        case .underline: return "下線"
        case .bullets: return "箇条書き"
        case .numbers: return "番号付きリスト"
        }
    }

    var symbol: String {
        switch self {
        case .bold: return "bold"
        case .underline: return "underline"
        case .bullets: return "list.bullet"
        case .numbers: return "list.number"
        }
    }

    var attribute: NSAttributedString.Key {
        switch self {
        case .bold: return .font
        case .underline: return .underlineStyle
        case .bullets, .numbers: return .paragraphStyle
        }
    }

    func matches(_ value: Any?) -> Bool {
        switch self {
        case .bold:
            guard let font = value as? NSFont else { return false }
            return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        case .underline:
            return (value as? Int ?? 0) != 0
        case .bullets, .numbers:
            guard let list = (value as? NSParagraphStyle)?.textLists.last else { return false }
            return list.isOrdered == (self == .numbers)
        }
    }
}

final class NoteTextView: PanelTextView {
    weak var notePanel: NativeNotePanel?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { notePanel?.note.content.primaryTextLayoutManager = textLayoutManager }
        return accepted
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditable, window?.firstResponder === self,
           event.modifierFlags.intersection([.command, .option, .shift, .control]) == .command {
            switch event.charactersIgnoringModifiers {
            case "b": notePanel?.apply(.bold); return true
            case "u": notePanel?.apply(.underline); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class NativeNotePanel: NSView, NSTextViewDelegate {
    let note: PanelNote
    let editor: NoteTextView
    private let notes: PanelNotes
    private let textLayout = NSTextLayoutManager()
    private let scroll = NSScrollView()
    private var buttons: [NSButton] = []
    private let retry = NSButton()

    init(note: PanelNote, notes: PanelNotes, openWebLink: @escaping (URL) -> Void) {
        self.note = note
        self.notes = notes
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        note.content.addTextLayoutManager(textLayout)
        textLayout.textContainer = container
        editor = NoteTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        wantsLayer = true
        editor.openWebLink = openWebLink
        editor.notePanel = self
        editor.delegate = self
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesAdaptiveColorMappingForDarkAppearance = true
        editor.setAccessibilityLabel("メモ本文")
        editor.textContainerInset = NSSize(width: 10, height: 6)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = .width
        container.widthTracksTextView = true
        if note.text.length == 0 { editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 14)] }
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor
        addSubview(scroll)
        for format in NoteFormat.allCases {
            let button = NSButton(image: NSImage(systemSymbolName: format.symbol, accessibilityDescription: format.label)!,
                                  target: self, action: #selector(formatClicked(_:)))
            button.tag = format.rawValue
            button.toolTip = format.label
            button.setAccessibilityLabel(format.label)
            button.setButtonType(.toggle)
            button.bezelStyle = .accessoryBarAction
            button.refusesFirstResponder = true
            buttons.append(button)
            addSubview(button)
        }
        retry.image = NSImage(systemSymbolName: "exclamationmark.arrow.triangle.2.circlepath", accessibilityDescription: "保存を再試行")
        retry.imagePosition = .imageOnly
        retry.bezelStyle = .accessoryBarAction
        retry.contentTintColor = .systemOrange
        retry.target = self
        retry.action = #selector(retrySave)
        retry.setAccessibilityLabel("メモを保存できませんでした。保存を再試行")
        addSubview(retry)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSaveStatus),
                                               name: PanelNote.saveStatusChanged, object: note)
        updateSaveStatus()
        updateButtons()
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { note.content.removeTextLayoutManager(textLayout) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { notes.save(note) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.textBackgroundColor.cgColor }
    }

    override func layout() {
        super.layout()
        let height: CGFloat = editor.isEditable ? min(30, bounds.height) : 0
        let count = buttons.count + (retry.isHidden ? 0 : 1)
        let width = min(29, max(1, (bounds.width - 8) / CGFloat(count)))
        for (index, button) in (buttons + [retry]).enumerated() {
            button.frame = NSRect(x: 4 + CGFloat(index) * width, y: bounds.height - height, width: width, height: height)
        }
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - height)
        editor.minSize = scroll.contentSize
        editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, editor.frame.height)))
    }

    func setLayoutEditing(_ active: Bool) {
        if active, window?.firstResponder === editor { window?.makeFirstResponder(nil) }
        editor.isEditable = !active
        for button in buttons { button.isHidden = active }
        updateSaveStatus()
        needsLayout = true
    }

    func textDidChange(_ notification: Notification) {
        notes.changed(note)
        updateButtons()
    }
    func textDidEndEditing(_ notification: Notification) { notes.save(note) }
    func textViewDidChangeSelection(_ notification: Notification) { updateButtons() }
    func undoManager(for view: NSTextView) -> UndoManager? { note.undo }

    @objc private func retrySave() { notes.save(note) }
    @objc private func updateSaveStatus() {
        retry.isHidden = note.saveError == nil || !editor.isEditable
        retry.toolTip = note.saveError.map { "メモを保存できませんでした。クリックして再試行。\n" + $0.localizedDescription }
        needsLayout = true
    }
    @objc private func formatClicked(_ sender: NSButton) {
        if let format = NoteFormat(rawValue: sender.tag) { apply(format) }
    }
    private func selectionUses(_ format: NoteFormat) -> Bool {
        let range = NSIntersectionRange(editor.selectedRange(), NSRange(location: 0, length: note.text.length))
        if range.length == 0 { return format.matches(editor.typingAttributes[format.attribute]) }
        var allMatch = true
        note.text.enumerateAttribute(format.attribute, in: range, options: .longestEffectiveRangeNotRequired) { value, _, stop in
            if !format.matches(value) { allMatch = false; stop.pointee = true }
        }
        return allMatch
    }
    private func updateButtons() {
        for (format, button) in zip(NoteFormat.allCases, buttons) {
            let active = selectionUses(format)
            button.state = active ? .on : .off
            button.contentTintColor = active ? .controlAccentColor : .labelColor
        }
    }

    func apply(_ format: NoteFormat) {
        guard editor.isEditable else { return }
        window?.makeFirstResponder(editor)
        let selection = editor.selectedRange()
        let enable = !selectionUses(format)
        let key = format.attribute
        let isList = key == .paragraphStyle
        let range = isList ? (editor.string as NSString).paragraphRange(for: selection) : selection
        var list: NSTextList?
        if isList && enable {
            // Continue the preceding list when formatting its next paragraph.
            if range.location > 0 {
                let previous = note.text.attribute(.paragraphStyle, at: range.location - 1, effectiveRange: nil) as? NSParagraphStyle
                if let last = previous?.textLists.last, last.isOrdered == (format == .numbers) { list = last }
            }
            if list == nil { list = NSTextList(markerFormat: format == .numbers ? .init(rawValue: "{decimal}.") : .disc, options: 0) }
        }
        func value(replacing old: Any?) -> Any {
            switch format {
            case .bold:
                let font = old as? NSFont ?? .systemFont(ofSize: 14)
                let manager = NSFontManager.shared
                return enable ? manager.convert(font, toHaveTrait: .boldFontMask) : manager.convert(font, toNotHaveTrait: .boldFontMask)
            case .underline: return enable ? NSUnderlineStyle.single.rawValue : 0
            case .bullets, .numbers:
                let style = (old as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.textLists = list.map { [$0] } ?? []
                return style
            }
        }
        if range.length == 0, isList, enable {
            // An empty paragraph needs a terminator to carry the list in TextKit and RTF.
            var attributes = editor.typingAttributes
            attributes[key] = value(replacing: attributes[key])
            editor.insertText(NSAttributedString(string: "\n", attributes: attributes), replacementRange: selection)
            editor.setSelectedRange(selection)
        } else if range.length > 0 {
            guard editor.shouldChangeText(in: range, replacementString: nil) else { return }
            note.content.performEditingTransaction {
                note.text.enumerateAttribute(key, in: range) { old, run, _ in
                    note.text.addAttribute(key, value: value(replacing: old), range: run)
                }
            }
            editor.didChangeText()
        }
        if selection.length == 0 {
            editor.typingAttributes[key] = value(replacing: editor.typingAttributes[key])
        }
        updateButtons()
    }
}
