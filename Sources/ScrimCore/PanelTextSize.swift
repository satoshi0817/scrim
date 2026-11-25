/// Display sizes for note and task panels. Raw values match the existing task-size preference.
public enum PanelTextSize: String, CaseIterable, Codable, Sendable {
    case extraSmall, small, standard, large, extraLarge

    public var title: String {
        switch self {
        case .extraSmall: return "極小"
        case .small: return "小"
        case .standard: return "中"
        case .large: return "大"
        case .extraLarge: return "極大"
        }
    }

    public static let standardNotePointSize: Double = 14

    /// Scale the editor, including pasted rich text, relative to the standard note size.
    public var noteMagnification: Double { notePointSize / Self.standardNotePointSize }

    private var notePointSize: Double {
        switch self {
        case .extraSmall: return 10
        case .small: return 12
        case .standard: return Self.standardNotePointSize
        case .large: return 17
        case .extraLarge: return 20
        }
    }

    /// Task names in the list and the opened task's title.
    public var task: Double {
        switch self {
        case .extraSmall: return 11
        case .small: return 13
        case .standard: return 15
        case .large: return 17
        case .extraLarge: return 20
        }
    }

    /// Due dates, assignees and other secondary lines.
    public var detail: Double {
        switch self {
        case .extraSmall: return 10
        case .small: return 11
        case .standard: return 12
        case .large: return 13
        case .extraLarge: return 15
        }
    }

    /// Page content of an opened task.
    public var body: Double {
        switch self {
        case .extraSmall: return 11
        case .small: return 13
        case .standard: return 14
        case .large: return 16
        case .extraLarge: return 18
        }
    }
}

public typealias NotionTextSize = PanelTextSize
