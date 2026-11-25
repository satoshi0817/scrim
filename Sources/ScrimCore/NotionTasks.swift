import Foundation

/// Requests, responses and column mapping for the native Notion task panel.
/// Pure data: networking and the token live in the app target.
public enum NotionAPI {
    public static let baseURL = URL(string: "https://api.notion.com")!
    public static let version = "2026-03-11"
    public static let pageSize = 100
    /// Upper bound per refresh, so a huge database never loads everything.
    public static let maximumTasks = 200
}

/// How one Notion data source maps onto Scrim's task fields. Stored in the panel URL as
/// property IDs, so renaming a column in Notion keeps the panel working.
public struct NotionTaskMapping: Equatable, Sendable {
    public enum Completion: Equatable, Sendable {
        case checkbox(property: String)
        /// `done` is the option set when completing. Every option in the same status group counts as complete.
        case status(property: String, done: String)
        public var property: String {
            switch self { case .checkbox(let id), .status(let id, _): return id }
        }
    }
    public var dataSourceID: String
    public var name: String
    public var titleProperty: String
    public var completion: Completion
    public var dueProperty: String?
    /// A people column, used to show and filter assignees.
    public var assigneeProperty: String?
    public init(dataSourceID: String, name: String, titleProperty: String, completion: Completion, dueProperty: String? = nil,
                assigneeProperty: String? = nil) {
        self.dataSourceID = dataSourceID; self.name = name; self.titleProperty = titleProperty
        self.completion = completion; self.dueProperty = dueProperty; self.assigneeProperty = assigneeProperty
    }
    public init?(queryItems items: [URLQueryItem]) {
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 } }
        guard let source = value("source"), let title = value("titleProp"), let done = value("doneProp") else { return nil }
        switch value("doneType") {
        case "checkbox": completion = .checkbox(property: done)
        case "status":
            guard let option = value("doneOption") else { return nil }
            completion = .status(property: done, done: option)
        default: return nil
        }
        dataSourceID = source; name = value("name") ?? ""; titleProperty = title; dueProperty = value("dueProp")
        assigneeProperty = value("assigneeProp")
    }
    public var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "source", value: dataSourceID), URLQueryItem(name: "name", value: name),
                     URLQueryItem(name: "titleProp", value: titleProperty)]
        switch completion {
        case .checkbox(let property):
            items += [URLQueryItem(name: "doneType", value: "checkbox"), URLQueryItem(name: "doneProp", value: property)]
        case .status(let property, let done):
            items += [URLQueryItem(name: "doneType", value: "status"), URLQueryItem(name: "doneProp", value: property),
                      URLQueryItem(name: "doneOption", value: done)]
        }
        if let dueProperty { items.append(URLQueryItem(name: "dueProp", value: dueProperty)) }
        if let assigneeProperty { items.append(URLQueryItem(name: "assigneeProp", value: assigneeProperty)) }
        return items
    }
}

/// One value of a status, select, multi-select or people property on a task.
public struct NotionChoice: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// How the task list is narrowed. Saved per panel (in its URL); the text filter is not saved.
public struct NotionTaskFilter: Equatable, Sendable {
    public enum Due: String, CaseIterable, Sendable {
        case all, overdue, today, week, none
        public var title: String {
            switch self { case .all: return "すべて"; case .overdue: return "期限切れ"; case .today: return "今日まで"; case .week: return "今週まで"; case .none: return "期限なし" }
        }
    }
    public var due: Due = .all
    /// A status, select or multi-select property and the option IDs to keep (any of them).
    public var choiceProperty: String?
    public var choiceValues: Set<String> = []
    /// User IDs on the mapping's assignee property (any of them).
    public var people: Set<String> = []
    public init(due: Due = .all, choiceProperty: String? = nil, choiceValues: Set<String> = [], people: Set<String> = []) {
        self.due = due; self.choiceProperty = choiceProperty; self.choiceValues = choiceValues; self.people = people
    }
    public var isActive: Bool { due != .all || (choiceProperty != nil && !choiceValues.isEmpty) || !people.isEmpty }
    public init(queryItems items: [URLQueryItem]) {
        due = items.first(where: { $0.name == "fdue" })?.value.flatMap(Due.init(rawValue:)) ?? .all
        choiceProperty = items.first(where: { $0.name == "fprop" })?.value.flatMap { $0.isEmpty ? nil : $0 }
        choiceValues = Set(items.filter { $0.name == "fval" }.compactMap(\.value))
        people = Set(items.filter { $0.name == "fperson" }.compactMap(\.value))
    }
    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if due != .all { items.append(URLQueryItem(name: "fdue", value: due.rawValue)) }
        if let choiceProperty, !choiceValues.isEmpty {
            items.append(URLQueryItem(name: "fprop", value: choiceProperty))
            items += choiceValues.sorted().map { URLQueryItem(name: "fval", value: $0) }
        }
        items += people.sorted().map { URLQueryItem(name: "fperson", value: $0) }
        return items
    }
    /// Text matches the title ignoring case, accents and full/half width; due buckets use the local calendar day and week.
    public func matches(_ task: NotionTask, text: String, assigneeProperty: String?, now: Date, calendar: Calendar = .current) -> Bool {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty && task.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == nil { return false }
        let day = task.due?.date(calendar: calendar).map { calendar.startOfDay(for: $0) }
        let today = calendar.startOfDay(for: now)
        switch due {
        case .all: break
        case .overdue: guard task.due?.isOverdue(now: now, calendar: calendar) == true else { return false }
        case .today: guard let day, day <= today else { return false }
        case .week:
            guard let day, let week = calendar.dateInterval(of: .weekOfYear, for: now), day < week.end else { return false }
        case .none: guard task.due == nil else { return false }
        }
        if let choiceProperty, !choiceValues.isEmpty {
            let values = Set((task.choices[choiceProperty] ?? []).map(\.id))
            guard !values.isDisjoint(with: choiceValues) else { return false }
        }
        if !people.isEmpty {
            guard let assigneeProperty else { return false }
            let assigned = Set((task.choices[assigneeProperty] ?? []).map(\.id))
            guard !assigned.isDisjoint(with: people) else { return false }
        }
        return true
    }
}

public struct NotionProperty: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case title, checkbox, status, date, select, multiSelect, people, other(String) }
    public struct Option: Equatable, Sendable, Identifiable {
        public var id: String; public var name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public struct Group: Equatable, Sendable, Identifiable {
        public var id: String; public var name: String; public var optionIDs: [String]
        public init(id: String, name: String, optionIDs: [String]) { self.id = id; self.name = name; self.optionIDs = optionIDs }
    }
    public var id: String
    public var name: String
    public var kind: Kind
    public var options: [Option]
    public var groups: [Group]
    public init(id: String, name: String, kind: Kind, options: [Option] = [], groups: [Group] = []) {
        self.id = id; self.name = name; self.kind = kind; self.options = options; self.groups = groups
    }
}

public struct NotionDataSourceSchema: Equatable, Sendable {
    public var id: String
    public var title: String
    public var properties: [NotionProperty]
    public init(id: String, title: String, properties: [NotionProperty]) { self.id = id; self.title = title; self.properties = properties }
    public func property(_ id: String) -> NotionProperty? { properties.first { $0.id == id } }
    public var titleProperty: NotionProperty? { properties.first { $0.kind == .title } }
    public var completionProperties: [NotionProperty] { properties.filter { $0.kind == .checkbox || ($0.kind == .status && !$0.options.isEmpty) } }
    public var dateProperties: [NotionProperty] { properties.filter { $0.kind == .date } }
    public var peopleProperties: [NotionProperty] { properties.filter { $0.kind == .people } }
    /// Status, select and multi-select columns: what the list can be filtered by besides due date and assignee.
    public var choiceProperties: [NotionProperty] { properties.filter { [.status, .select, .multiSelect].contains($0.kind) && !$0.options.isEmpty } }
    /// The status option that means "done": the first option in a group named Complete/完了, else the last group's first option.
    public static func defaultDoneOption(_ property: NotionProperty) -> String? {
        let complete = property.groups.first { ["complete", "completed", "done", "完了"].contains($0.name.lowercased()) } ?? property.groups.last
        return complete?.optionIDs.first ?? property.options.last?.id
    }
    /// Best guess: the title, a checkbox or status column for completion, and the first date column.
    public func defaultMapping() -> NotionTaskMapping? {
        guard let title = titleProperty, let done = completionProperties.first else { return nil }
        let completion: NotionTaskMapping.Completion
        if done.kind == .checkbox { completion = .checkbox(property: done.id) }
        else {
            guard let option = Self.defaultDoneOption(done) else { return nil }
            completion = .status(property: done.id, done: option)
        }
        return NotionTaskMapping(dataSourceID: id, name: self.title, titleProperty: title.id,
                                 completion: completion, dueProperty: dateProperties.first?.id, assigneeProperty: peopleProperties.first?.id)
    }
    /// Option IDs that count as complete for a status mapping: the whole group containing the done option.
    public func completeOptionIDs(_ mapping: NotionTaskMapping) -> [String] {
        guard case .status(let id, let done) = mapping.completion, let property = property(id) else { return [] }
        return property.groups.first { $0.optionIDs.contains(done) }?.optionIDs ?? [done]
    }
    /// Nil when every mapped column still exists with the expected type.
    public func mappingProblem(_ mapping: NotionTaskMapping) -> String? {
        guard property(mapping.titleProperty)?.kind == .title else { return "タイトルの列が見つかりません。" }
        switch mapping.completion {
        case .checkbox(let id):
            guard property(id)?.kind == .checkbox else { return "完了の列（チェックボックス）が見つかりません。" }
        case .status(let id, let done):
            guard let status = property(id), status.kind == .status else { return "完了の列（ステータス）が見つかりません。" }
            guard status.options.contains(where: { $0.id == done }) else { return "完了にするステータスの選択肢が見つかりません。" }
        }
        if let due = mapping.dueProperty, property(due)?.kind != .date { return "期限の列（日付）が見つかりません。" }
        if let assignee = mapping.assigneeProperty, property(assignee)?.kind != .people { return "担当者の列（ユーザー）が見つかりません。" }
        return nil
    }
}

/// A Notion date value. Date-only values carry no time zone and mean that calendar day.
public struct NotionDate: Equatable, Sendable {
    public var start: String
    public init(start: String) { self.start = start }
    public init(day: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        start = String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
    public var hasTime: Bool { start.contains("T") }
    public func date(calendar: Calendar = .current) -> Date? {
        if !hasTime {
            let parts = start.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: start) ?? ISO8601DateFormatter().date(from: start)
    }
    /// Overdue means the day (or moment) has passed; a date-only task is due through the end of its day.
    public func isOverdue(now: Date, calendar: Calendar = .current) -> Bool {
        guard let date = date(calendar: calendar) else { return false }
        if hasTime { return date < now }
        return calendar.startOfDay(for: now) > date
    }
}

public struct NotionTask: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var due: NotionDate?
    public var url: URL?
    public var checked: Bool?
    public var statusOptionID: String?
    public var createdTime: String
    /// Status, select, multi-select and people values, by property ID.
    public var choices: [String: [NotionChoice]]
    public init(id: String, title: String, due: NotionDate? = nil, url: URL? = nil, checked: Bool? = nil, statusOptionID: String? = nil,
                createdTime: String = "", choices: [String: [NotionChoice]] = [:]) {
        self.id = id; self.title = title; self.due = due; self.url = url; self.checked = checked
        self.statusOptionID = statusOptionID; self.createdTime = createdTime; self.choices = choices
    }
    /// Due tasks first, earliest first; undated tasks keep creation order after them.
    public static func ordered(_ tasks: [NotionTask], calendar: Calendar = .current) -> [NotionTask] {
        tasks.sorted { a, b in
            let x = a.due?.date(calendar: calendar), y = b.due?.date(calendar: calendar)
            switch (x, y) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.createdTime == b.createdTime ? a.id < b.id : a.createdTime < b.createdTime
            }
        }
    }
}

/// A run of text in a block, with the formatting Scrim shows.
public struct NotionRichText: Equatable, Sendable {
    public var text: String
    public var bold = false, italic = false, strikethrough = false, underline = false, code = false
    public var href: String?
    /// "text", "mention" or "equation".
    public var kind = "text"
    public init(text: String, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false, underline: Bool = false,
                code: Bool = false, href: String? = nil, kind: String = "text") {
        self.text = text; self.bold = bold; self.italic = italic; self.strikethrough = strikethrough; self.underline = underline
        self.code = code; self.href = href; self.kind = kind
    }
    /// Plain runs can be rewritten as text without losing anything.
    public var isPlain: Bool { kind == "text" && !bold && !italic && !strikethrough && !underline && !code && href == nil }
}

/// One block of a task's page content. Children are loaded a few levels deep.
public struct NotionBlock: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case paragraph, heading(Int), bulleted, numbered, todo, toggle, quote, callout, code, divider
        case image, bookmark, childPage, childDatabase, table, other(String)
        init(type: String) {
            switch type {
            case "paragraph": self = .paragraph
            case "heading_1": self = .heading(1)
            case "heading_2": self = .heading(2)
            case "heading_3": self = .heading(3)
            case "heading_4": self = .heading(4)
            case "bulleted_list_item": self = .bulleted
            case "numbered_list_item": self = .numbered
            case "to_do": self = .todo
            case "toggle": self = .toggle
            case "quote": self = .quote
            case "callout": self = .callout
            case "code": self = .code
            case "divider": self = .divider
            case "image": self = .image
            case "bookmark", "link_preview", "embed": self = .bookmark
            case "child_page": self = .childPage
            case "child_database": self = .childDatabase
            case "table": self = .table
            default: self = .other(type)
            }
        }
        /// The API's type name (and the key of its content object).
        public var typeKey: String {
            switch self {
            case .paragraph: return "paragraph"
            case .heading(let level): return "heading_\(level)"
            case .bulleted: return "bulleted_list_item"
            case .numbered: return "numbered_list_item"
            case .todo: return "to_do"
            case .toggle: return "toggle"
            case .quote: return "quote"
            case .callout: return "callout"
            case .code: return "code"
            case .divider: return "divider"
            case .image: return "image"
            case .bookmark: return "bookmark"
            case .childPage: return "child_page"
            case .childDatabase: return "child_database"
            case .table: return "table"
            case .other(let type): return type
            }
        }
        /// Blocks that hold rich text Scrim can rewrite.
        public var holdsText: Bool {
            switch self {
            case .paragraph, .heading, .bulleted, .numbered, .todo, .toggle, .quote, .callout, .code: return true
            default: return false
            }
        }
        /// Children worth loading: list items, toggles, quotes and callouts nest content; pages and tables do not.
        public var loadsChildren: Bool {
            switch self {
            case .paragraph, .heading, .bulleted, .numbered, .todo, .toggle, .quote, .callout: return true
            default: return false
            }
        }
    }
    public var id: String
    public var kind: Kind
    public var text: [NotionRichText]
    public var checked: Bool
    /// Image or bookmark address.
    public var url: URL?
    /// Child page or database title, code language, or the type name of an unknown block.
    public var label: String
    /// Callout emoji.
    public var icon: String?
    public var hasChildren: Bool
    public var children: [NotionBlock]
    public init(id: String, kind: Kind, text: [NotionRichText] = [], checked: Bool = false, url: URL? = nil, label: String = "",
                icon: String? = nil, hasChildren: Bool = false, children: [NotionBlock] = []) {
        self.id = id; self.kind = kind; self.text = text; self.checked = checked; self.url = url; self.label = label
        self.icon = icon; self.hasChildren = hasChildren; self.children = children
    }
    public var plainText: String { text.map(\.text).joined() }
    /// Text blocks without formatting, links or mentions can be edited in Scrim; others stay read-only so
    /// nothing is lost. To-do checkboxes can always be toggled.
    public var isEditable: Bool { kind.holdsText && text.allSatisfy(\.isPlain) }
    /// Finds a block anywhere in a tree.
    public static func find(_ id: String, in blocks: [NotionBlock]) -> NotionBlock? {
        for block in blocks {
            if block.id == id { return block }
            if let found = find(id, in: block.children) { return found }
        }
        return nil
    }
    /// Replaces (or with nil, removes) a block anywhere in a tree, keeping loaded children when the update has none.
    public static func replacing(_ id: String, with block: NotionBlock?, in blocks: [NotionBlock]) -> [NotionBlock] {
        blocks.compactMap { current in
            if current.id == id {
                guard var block else { return nil }
                if block.children.isEmpty { block.children = current.children }
                return block
            }
            var copy = current; copy.children = replacing(id, with: block, in: current.children); return copy
        }
    }
}

public struct NotionSearchResult: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case dataSource = "data_source", page }
    public var id: String
    public var title: String
    public var kind: Kind
    public init(id: String, title: String, kind: Kind) { self.id = id; self.title = title; self.kind = kind }
}

/// Reads a Notion object ID from a pasted link or ID: "Copy link" URLs (notion.so, notion.site, app.notion.com,
/// notion://), with or without a view (`?v=`), or a bare 32-character ID with or without dashes.
public enum NotionLink {
    public static func objectID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = normalizedID(trimmed) { return id }
        guard let parts = URLComponents(string: trimmed), let scheme = parts.scheme?.lowercased(), ["https", "http", "notion"].contains(scheme),
              let host = parts.host?.lowercased(), parts.user == nil, parts.password == nil,
              ["notion.so", "notion.site", "notion.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              host != "calendar.notion.com" else { return nil }
        // The object is named in the path ("Title-<id>" or "<id>"); ?v= is a view and ?p= a peeked page.
        for component in parts.path.split(separator: "/").reversed() {
            if let match = component.range(of: #"[0-9a-fA-F]{32}$|[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$"#, options: .regularExpression),
               let id = normalizedID(String(component[match])) { return id }
        }
        return nil
    }
    private static func normalizedID(_ text: String) -> String? {
        let hex = text.replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit),
              text.count == 32 || text.range(of: #"^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil else { return nil }
        let c = Array(hex)
        return [c[0..<8], c[8..<12], c[12..<16], c[16..<20], c[20..<32]].map { String($0) }.joined(separator: "-")
    }
}

public struct NotionRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [URLQueryItem]
    /// JSON-encoded body, or nil for GET.
    public var body: Data?
    public init(method: String, path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil) {
        self.method = method; self.path = path; self.query = query
        body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
    }
    public func urlRequest(baseURL: URL, token: String) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.queryItems = query; url = parts.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(NotionAPI.version, forHTTPHeaderField: "Notion-Version")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.timeoutInterval = 20
        return request
    }
}

public enum NotionRequests {
    public static func me() -> NotionRequest { NotionRequest(method: "GET", path: "v1/users/me") }
    public static func search(_ kind: NotionSearchResult.Kind, query: String) -> NotionRequest {
        var body: [String: Any] = ["filter": ["property": "object", "value": kind.rawValue], "page_size": NotionAPI.pageSize,
                                   "sort": ["timestamp": "last_edited_time", "direction": "descending"]]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["query"] = trimmed }
        return NotionRequest(method: "POST", path: "v1/search", json: body)
    }
    public static func dataSource(_ id: String) -> NotionRequest { NotionRequest(method: "GET", path: "v1/data_sources/\(id)") }
    public static func database(_ id: String) -> NotionRequest { NotionRequest(method: "GET", path: "v1/databases/\(id)") }
    /// Open tasks only. Completion is decided by the mapped checkbox or the done option's status group.
    public static func openTasks(_ mapping: NotionTaskMapping, schema: NotionDataSourceSchema, cursor: String? = nil) -> NotionRequest {
        let filter: [String: Any]
        switch mapping.completion {
        case .checkbox(let property): filter = ["property": property, "checkbox": ["equals": false]]
        case .status(let property, _):
            let names = schema.completeOptionIDs(mapping).compactMap { id in schema.property(property)?.options.first { $0.id == id }?.name }
            let clauses: [[String: Any]] = names.map { ["property": property, "status": ["does_not_equal": $0]] }
            filter = clauses.count == 1 ? clauses[0] : ["and": clauses]
        }
        var body: [String: Any] = ["filter": filter, "page_size": NotionAPI.pageSize,
                                   "sorts": [["timestamp": "created_time", "direction": "ascending"]]]
        if let cursor { body["start_cursor"] = cursor }
        return NotionRequest(method: "POST", path: "v1/data_sources/\(mapping.dataSourceID)/query", json: body)
    }
    public static func createTask(_ mapping: NotionTaskMapping, title: String, due: NotionDate?) -> NotionRequest {
        var properties: [String: Any] = [mapping.titleProperty: titleValue(title)]
        if let property = mapping.dueProperty, let due { properties[property] = ["date": ["start": due.start]] }
        return NotionRequest(method: "POST", path: "v1/pages", json: [
            "parent": ["type": "data_source_id", "data_source_id": mapping.dataSourceID], "properties": properties])
    }
    /// `due: .some(nil)` clears the date. `statusOptionID` is only used to undo a status completion.
    public static func updateTask(_ id: String, _ mapping: NotionTaskMapping, title: String? = nil, due: NotionDate?? = nil,
                                  completed: Bool? = nil, restoreStatusOptionID: String? = nil, statusOptionID: String? = nil) -> NotionRequest {
        var properties: [String: Any] = [:]
        if let statusOptionID, case .status(let property, _) = mapping.completion { properties[property] = ["status": ["id": statusOptionID]] }
        if let title { properties[mapping.titleProperty] = titleValue(title) }
        if let property = mapping.dueProperty, let due {
            properties[property] = due.map { ["date": ["start": $0.start]] } ?? ["date": NSNull()]
        }
        if let completed {
            switch mapping.completion {
            case .checkbox(let property): properties[property] = ["checkbox": completed]
            case .status(let property, let done):
                if completed { properties[property] = ["status": ["id": done]] }
                else { properties[property] = ["status": restoreStatusOptionID.map { ["id": $0] as Any } ?? NSNull()] }
            }
        }
        return NotionRequest(method: "PATCH", path: "v1/pages/\(id)", json: ["properties": properties])
    }
    /// A new task database under a page: title, completion checkbox and due date.
    public static func createTaskDatabase(parentPage: String, title: String) -> NotionRequest {
        NotionRequest(method: "POST", path: "v1/databases", json: [
            "parent": ["type": "page_id", "page_id": parentPage],
            "title": [["type": "text", "text": ["content": title]]],
            "initial_data_source": ["properties": [
                NotionTaskDatabase.titleName: ["title": [String: Any]()],
                NotionTaskDatabase.doneName: ["checkbox": [String: Any]()],
                NotionTaskDatabase.dueName: ["date": [String: Any]()],
            ]],
        ])
    }
    private static func titleValue(_ text: String) -> [String: Any] { ["title": richText(text)] }
    /// Plain text as rich text, split into pieces of at most 2000 characters (the API limit), at most 100 pieces.
    public static func richText(_ text: String) -> [[String: Any]] {
        var pieces: [[String: Any]] = [], rest = Substring(text)
        repeat {
            let piece = rest.prefix(2000); rest = rest.dropFirst(piece.count)
            pieces.append(["type": "text", "text": ["content": String(piece)]])
        } while !rest.isEmpty && pieces.count < 100
        return pieces
    }
    // MARK: Page content
    public static func blockChildren(_ id: String, cursor: String? = nil) -> NotionRequest {
        var query = [URLQueryItem(name: "page_size", value: String(NotionAPI.pageSize))]
        if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
        return NotionRequest(method: "GET", path: "v1/blocks/\(id)/children", query: query)
    }
    /// Replaces a text block's content. Only used for blocks whose text has no formatting, so nothing is lost.
    public static func updateBlockText(_ block: NotionBlock, text: String) -> NotionRequest {
        NotionRequest(method: "PATCH", path: "v1/blocks/\(block.id)", json: [block.kind.typeKey: ["rich_text": richText(text)]])
    }
    public static func setChecked(_ blockID: String, _ checked: Bool) -> NotionRequest {
        NotionRequest(method: "PATCH", path: "v1/blocks/\(blockID)", json: ["to_do": ["checked": checked]])
    }
    /// Adds a block at the end of a page.
    public static func appendBlock(to pageID: String, kind: NotionBlock.Kind, text: String) -> NotionRequest {
        var content: [String: Any] = ["rich_text": richText(text)]
        if kind == .todo { content["checked"] = false }
        return NotionRequest(method: "PATCH", path: "v1/blocks/\(pageID)/children", json: [
            "children": [["object": "block", "type": kind.typeKey, kind.typeKey: content]], "position": ["type": "end"]])
    }
    /// Moves a block to Trash (restorable in Notion).
    public static func deleteBlock(_ id: String) -> NotionRequest { NotionRequest(method: "DELETE", path: "v1/blocks/\(id)") }
}

public enum NotionTaskDatabase {
    public static let defaultTitle = "Scrimのタスク"
    public static let titleName = "タスク名"
    public static let doneName = "完了"
    public static let dueName = "期限"
}

public struct NotionAPIError: Error, Equatable, Sendable {
    public var status: Int
    public var code: String
    public var retryAfter: TimeInterval?
    public init(status: Int, code: String, retryAfter: TimeInterval? = nil) { self.status = status; self.code = code; self.retryAfter = retryAfter }
    public static let network = NotionAPIError(status: 0, code: "network")
    public static let missingToken = NotionAPIError(status: 0, code: "missing_token")
    public static let invalidResponse = NotionAPIError(status: 0, code: "invalid_response")
    public var isRetryable: Bool { status == 429 || status == 500 || status == 502 || status == 503 || status == 504 || status == 529 || code == "network" }
    /// True when the mapping (not the token) needs attention.
    public var needsMapping: Bool { status == 400 && code == "validation_error" }
    public var message: String {
        switch (status, code) {
        case (0, "missing_token"): return "Notionのトークンが未登録です。設定 → パネル →「Notion」で登録してください。"
        case (0, "network"): return "Notionに接続できません。通信状況を確認してください。"
        case (401, _): return "Notionのトークンが無効か、有効期限が切れています。設定 → パネル →「Notion」で登録し直してください。"
        case (403, _): return "この操作の権限がありません。Notionの接続に、コンテンツの読み取り・挿入・更新の機能があるか確認してください。"
        case (404, _): return "このデータベースを開けません。Notionでデータベースの「•••」→「接続」から、Scrimに登録したトークンの接続を追加してください。"
        case (400, "validation_error"): return "Notionのデータベースの列が変わった可能性があります。パネルのメニューから「データベースと列を設定」を開いてください。"
        case (429, _): return "Notionへのリクエストが多すぎます。しばらくしてから再度読み込みます。"
        case (409, _): return "Notion側で同時に更新されました。もう一度お試しください。"
        case (500..., _): return "Notionが混み合っています。しばらくしてから再度読み込みます。"
        default: return "Notionで問題が発生しました（\(status) \(code)）。"
        }
    }
}

public enum NotionResponses {
    public static func error(status: Int, data: Data, retryAfter: String? = nil) -> NotionAPIError {
        let code = (json(data)?["code"] as? String) ?? "http_\(status)"
        return NotionAPIError(status: status, code: code, retryAfter: retryAfter.flatMap(TimeInterval.init))
    }
    public static func cursor(_ data: Data) -> String? {
        guard let object = json(data), object["has_more"] as? Bool == true else { return nil }
        return object["next_cursor"] as? String
    }
    public static func search(_ data: Data) throws -> [NotionSearchResult] {
        guard let results = json(data)?["results"] as? [[String: Any]] else { throw NotionAPIError.invalidResponse }
        return results.compactMap { item in
            guard let id = item["id"] as? String, let object = item["object"] as? String,
                  let kind = NotionSearchResult.Kind(rawValue: object), !isRemoved(item) else { return nil }
            return NotionSearchResult(id: id, title: title(of: item), kind: kind)
        }
    }
    public static func dataSource(_ data: Data) throws -> NotionDataSourceSchema {
        guard let object = json(data), let id = object["id"] as? String,
              let properties = object["properties"] as? [String: [String: Any]] else { throw NotionAPIError.invalidResponse }
        let parsed = properties.compactMap { name, value -> NotionProperty? in
            guard let id = value["id"] as? String, let type = value["type"] as? String else { return nil }
            let kind: NotionProperty.Kind
            switch type {
            case "title": kind = .title
            case "checkbox": kind = .checkbox
            case "status": kind = .status
            case "date": kind = .date
            case "select": kind = .select
            case "multi_select": kind = .multiSelect
            case "people": kind = .people
            default: kind = .other(type)
            }
            let status = value["status"] as? [String: Any]
            let optionSource = status ?? (value["select"] as? [String: Any]) ?? (value["multi_select"] as? [String: Any])
            let options = (optionSource?["options"] as? [[String: Any]] ?? []).compactMap { option -> NotionProperty.Option? in
                guard let id = option["id"] as? String, let name = option["name"] as? String else { return nil }
                return NotionProperty.Option(id: id, name: name)
            }
            let groups = (status?["groups"] as? [[String: Any]] ?? []).compactMap { group -> NotionProperty.Group? in
                guard let id = group["id"] as? String, let name = group["name"] as? String else { return nil }
                return NotionProperty.Group(id: id, name: name, optionIDs: group["option_ids"] as? [String] ?? [])
            }
            return NotionProperty(id: id, name: (value["name"] as? String) ?? name, kind: kind, options: options, groups: groups)
        }
        // Title first, then by name, so pickers are stable.
        let sorted = parsed.sorted { ($0.kind == .title ? 0 : 1, $0.name) < ($1.kind == .title ? 0 : 1, $1.name) }
        return NotionDataSourceSchema(id: id, title: title(of: object), properties: sorted)
    }
    public static func tasks(_ data: Data, mapping: NotionTaskMapping) throws -> [NotionTask] {
        guard let results = json(data)?["results"] as? [[String: Any]] else { throw NotionAPIError.invalidResponse }
        return results.compactMap { task(from: $0, mapping: mapping) }
    }
    public static func task(_ data: Data, mapping: NotionTaskMapping) throws -> NotionTask {
        guard let object = json(data), let task = task(from: object, mapping: mapping) else { throw NotionAPIError.invalidResponse }
        return task
    }
    /// The data sources of a database (one for most databases).
    public static func databaseSources(_ data: Data) throws -> [NotionSearchResult] {
        guard let object = json(data), let sources = object["data_sources"] as? [[String: Any]] else { throw NotionAPIError.invalidResponse }
        let databaseTitle = title(of: object)
        return sources.compactMap { source in
            guard let id = source["id"] as? String else { return nil }
            let name = (source["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? databaseTitle
            return NotionSearchResult(id: id, title: name, kind: .dataSource)
        }
    }
    /// Full blocks from a children list; partial entries (only an ID) are skipped.
    public static func blocks(_ data: Data) throws -> [NotionBlock] {
        guard let results = json(data)?["results"] as? [[String: Any]] else { throw NotionAPIError.invalidResponse }
        return results.compactMap(block(from:))
    }
    public static func block(_ data: Data) throws -> NotionBlock {
        guard let object = json(data), let block = block(from: object) else { throw NotionAPIError.invalidResponse }
        return block
    }
    static func block(from object: [String: Any]) -> NotionBlock? {
        guard let id = object["id"] as? String, let type = object["type"] as? String, !isRemoved(object) else { return nil }
        let content = object[type] as? [String: Any] ?? [:]
        let kind = NotionBlock.Kind(type: type)
        let text = (content["rich_text"] as? [[String: Any]] ?? []).map(richText(from:))
        var url: URL?
        if let file = content["file"] as? [String: Any] { url = (file["url"] as? String).flatMap(URL.init(string:)) }
        if let external = content["external"] as? [String: Any] { url = (external["url"] as? String).flatMap(URL.init(string:)) }
        if url == nil { url = (content["url"] as? String).flatMap(URL.init(string:)) }
        let label: String
        switch kind {
        case .childPage, .childDatabase: label = content["title"] as? String ?? ""
        case .code: label = content["language"] as? String ?? ""
        case .other: label = (content["block_type"] as? String) ?? type
        default: label = ""
        }
        let icon = (content["icon"] as? [String: Any])?["emoji"] as? String
        return NotionBlock(id: id, kind: kind, text: text, checked: content["checked"] as? Bool ?? false, url: url, label: label,
                           icon: icon, hasChildren: object["has_children"] as? Bool ?? false)
    }
    private static func richText(from run: [String: Any]) -> NotionRichText {
        let annotations = run["annotations"] as? [String: Any] ?? [:]
        func flag(_ key: String) -> Bool { annotations[key] as? Bool ?? false }
        let link = ((run["text"] as? [String: Any])?["link"] as? [String: Any])?["url"] as? String
        return NotionRichText(text: run["plain_text"] as? String ?? (run["text"] as? [String: Any])?["content"] as? String ?? "",
                              bold: flag("bold"), italic: flag("italic"), strikethrough: flag("strikethrough"), underline: flag("underline"),
                              code: flag("code"), href: run["href"] as? String ?? link, kind: run["type"] as? String ?? "text")
    }
    /// The first data source of a database that was just created.
    public static func createdDataSourceID(_ data: Data) throws -> String {
        guard let sources = json(data)?["data_sources"] as? [[String: Any]], let id = sources.first?["id"] as? String else {
            throw NotionAPIError.invalidResponse
        }
        return id
    }
    private static func task(from object: [String: Any], mapping: NotionTaskMapping) -> NotionTask? {
        guard let id = object["id"] as? String, !isRemoved(object) else { return nil }
        let properties = (object["properties"] as? [String: [String: Any]] ?? [:]).values
        func value(_ property: String?) -> [String: Any]? { property.flatMap { p in properties.first { $0["id"] as? String == p } } }
        let title = plainText(value(mapping.titleProperty)?["title"])
        let due = ((value(mapping.dueProperty)?["date"] as? [String: Any])?["start"] as? String).map(NotionDate.init(start:))
        let completion = value(mapping.completion.property)
        let checked = completion?["checkbox"] as? Bool
        let status = (completion?["status"] as? [String: Any])?["id"] as? String
        var choices: [String: [NotionChoice]] = [:]
        for property in properties {
            guard let propertyID = property["id"] as? String else { continue }
            func choice(_ value: Any?) -> NotionChoice? {
                guard let value = value as? [String: Any], let id = value["id"] as? String else { return nil }
                return NotionChoice(id: id, name: value["name"] as? String ?? "")
            }
            switch property["type"] as? String {
            case "status": choices[propertyID] = choice(property["status"]).map { [$0] } ?? []
            case "select": choices[propertyID] = choice(property["select"]).map { [$0] } ?? []
            case "multi_select": choices[propertyID] = (property["multi_select"] as? [Any] ?? []).compactMap(choice)
            case "people": choices[propertyID] = (property["people"] as? [Any] ?? []).compactMap(choice)
            default: break
            }
        }
        return NotionTask(id: id, title: title, due: due, url: (object["url"] as? String).flatMap(URL.init(string:)),
                          checked: checked, statusOptionID: status, createdTime: object["created_time"] as? String ?? "", choices: choices)
    }
    private static func title(of object: [String: Any]) -> String {
        if let title = object["title"] as? [[String: Any]] { return plainText(title) }
        let properties = object["properties"] as? [String: [String: Any]] ?? [:]
        return plainText(properties.values.first { $0["type"] as? String == "title" }?["title"])
    }
    private static func plainText(_ value: Any?) -> String {
        (value as? [[String: Any]] ?? []).compactMap { $0["plain_text"] as? String ?? ($0["text"] as? [String: Any])?["content"] as? String }.joined()
    }
    /// 2026-03-11 reports trash as `in_trash` and archiving as `is_archived`; older payloads used `archived`.
    private static func isRemoved(_ object: [String: Any]) -> Bool {
        ["in_trash", "is_archived", "archived"].contains { object[$0] as? Bool == true }
    }
    private static func json(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
}
