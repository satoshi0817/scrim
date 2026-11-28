import AppKit
import SwiftUI
import ScrimCore

/// Text size for Notion task panels, from Settings. Shared so every panel updates at once.
extension NotionClient {
    /// A task's page content: top-level blocks plus nested children a few levels deep, capped so huge pages stay
    /// cheap. Returns whether the cap cut anything off.
    func pageContent(_ pageID: String, maxDepth: Int = 3, maxBlocks: Int = 400) async throws -> (blocks: [NotionBlock], truncated: Bool) {
        var loaded = 0, truncated = false
        func children(of id: String, depth: Int) async throws -> [NotionBlock] {
            var result: [NotionBlock] = [], cursor: String?
            repeat {
                let data = try await send(NotionRequests.blockChildren(id, cursor: cursor))
                result += try NotionResponses.blocks(data)
                cursor = NotionResponses.cursor(data)
            } while cursor != nil && loaded + result.count < maxBlocks
            if cursor != nil { truncated = true }
            loaded += result.count
            for index in result.indices where result[index].hasChildren && result[index].kind.loadsChildren {
                guard depth < maxDepth, loaded < maxBlocks else { truncated = true; break }
                result[index].children = try await children(of: result[index].id, depth: depth + 1)
            }
            return result
        }
        let blocks = try await children(of: pageID, depth: 1)
        return (blocks, truncated)
    }
    func updateBlockText(_ block: NotionBlock, text: String) async throws -> NotionBlock {
        try NotionResponses.block(await send(NotionRequests.updateBlockText(block, text: text)))
    }
    func setChecked(_ blockID: String, _ checked: Bool) async throws -> NotionBlock {
        try NotionResponses.block(await send(NotionRequests.setChecked(blockID, checked)))
    }
    func appendBlock(to pageID: String, kind: NotionBlock.Kind, text: String) async throws -> [NotionBlock] {
        try NotionResponses.blocks(await send(NotionRequests.appendBlock(to: pageID, kind: kind, text: text)))
    }
    func deleteBlock(_ id: String) async throws { _ = try await send(NotionRequests.deleteBlock(id)) }
}

/// One task opened in the panel: its properties and page content, with editing.
@MainActor final class NotionTaskDetailModel: ObservableObject {
    @Published private(set) var task: NotionTask
    let mapping: NotionTaskMapping
    let schema: NotionDataSourceSchema?
    @Published private(set) var blocks: [NotionBlock] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var truncated = false
    @Published var error: String?
    @Published private(set) var saving: Set<String> = []
    @Published var editingBlock: String?
    @Published var blockDraft = ""
    @Published var editingTitle = false
    @Published var titleDraft = ""
    @Published var confirmingDelete: String?
    var onTaskChange: ((NotionTask) -> Void)?
    var onOpenPage: ((URL) -> Void)?
    var onComplete: ((NotionTask) -> Void)?
    private var loadTask: Task<Void, Never>?

    init(task: NotionTask, mapping: NotionTaskMapping, schema: NotionDataSourceSchema?) {
        self.task = task; self.mapping = mapping; self.schema = schema
    }
    private var client: NotionClient { NotionEnvironment.current.client }

    func load() {
        loadTask?.cancel()
        loading = true; error = nil
        let client = self.client, id = task.id
        loadTask = Task { [weak self] in
            do {
                let content = try await client.pageContent(id)
                guard let self, !Task.isCancelled else { return }
                self.blocks = content.blocks; self.truncated = content.truncated; self.loaded = true
            } catch is CancellationError {
            } catch {
                self?.error = (error as? NotionAPIError ?? .network).message
            }
            self?.loading = false
        }
    }
    func cancel() { loadTask?.cancel(); loadTask = nil }
    func openInNotion() { if let url = task.url { onOpenPage?(url) } }

    // MARK: Properties

    var statusProperty: NotionProperty? {
        guard case .status(let id, _) = mapping.completion else { return nil }
        return schema?.property(id)
    }
    /// Read-only tags shown under the title: select and multi-select values.
    var tags: [(property: String, values: [String])] {
        guard let schema else { return [] }
        return schema.properties.filter { $0.kind == .select || $0.kind == .multiSelect }.compactMap { property in
            let names = (task.choices[property.id] ?? []).map(\.name).filter { !$0.isEmpty }
            return names.isEmpty ? nil : (property.name, names)
        }
    }
    var assignees: [String] { mapping.assigneeProperty.flatMap { task.choices[$0] }?.map(\.name).filter { !$0.isEmpty } ?? [] }

    func beginTitleEdit() { titleDraft = task.title; editingTitle = true }
    func cancelTitleEdit() { editingTitle = false; titleDraft = "" }
    func saveTitle() {
        let text = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTitle = false
        guard !text.isEmpty, text != task.title else { return }
        updateTask(title: text)
    }
    func setDue(_ date: Date?) {
        let value = date.map { NotionDate(day: $0) }
        guard mapping.dueProperty != nil, value != task.due else { return }
        updateTask(due: .some(value))
    }
    func setStatus(_ optionID: String) {
        guard optionID != task.statusOptionID else { return }
        updateTask(status: optionID)
    }
    private func updateTask(title: String? = nil, due: NotionDate?? = nil, status: String? = nil) {
        let client = self.client, mapping = self.mapping, id = task.id
        saving.insert("task")
        Task { [weak self] in
            do {
                let updated = try await client.update(id, mapping, title: title, due: due, statusOptionID: status)
                self?.task = updated; self?.onTaskChange?(updated); self?.error = nil
            } catch {
                self?.error = (error as? NotionAPIError ?? .network).message
            }
            self?.saving.remove("task")
        }
    }

    // MARK: Content

    func beginEdit(_ block: NotionBlock) {
        guard block.isEditable else { return }
        editingBlock = block.id; blockDraft = block.plainText; confirmingDelete = nil
    }
    func cancelEdit() { editingBlock = nil; blockDraft = "" }
    func saveBlock() {
        guard let id = editingBlock, let block = NotionBlock.find(id, in: blocks) else { return }
        let text = blockDraft
        editingBlock = nil
        guard text != block.plainText else { return }
        run(id) { client in
            let updated = try await client.updateBlockText(block, text: text)
            self.blocks = NotionBlock.replacing(id, with: updated, in: self.blocks)
        }
    }
    func toggleChecked(_ block: NotionBlock) {
        guard block.kind == .todo else { return }
        let next = !block.checked
        var optimistic = block; optimistic.checked = next
        blocks = NotionBlock.replacing(block.id, with: optimistic, in: blocks)
        run(block.id, revert: block) { client in
            let updated = try await client.setChecked(block.id, next)
            self.blocks = NotionBlock.replacing(block.id, with: updated, in: self.blocks)
        }
    }
    func append(_ text: String, kind: NotionBlock.Kind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let page = task.id
        run("append") { client in
            let added = try await client.appendBlock(to: page, kind: kind, text: trimmed)
            self.blocks += added
        }
    }
    /// The first tap asks for confirmation; the second moves the block to Notion's Trash.
    func delete(_ block: NotionBlock) {
        guard confirmingDelete == block.id else { confirmingDelete = block.id; return }
        confirmingDelete = nil; editingBlock = nil
        run(block.id) { client in
            try await client.deleteBlock(block.id)
            self.blocks = NotionBlock.replacing(block.id, with: nil, in: self.blocks)
        }
    }
    private func run(_ key: String, revert: NotionBlock? = nil, _ work: @escaping (NotionClient) async throws -> Void) {
        let client = self.client
        saving.insert(key)
        Task { [weak self] in
            do { try await work(client); self?.error = nil }
            catch {
                guard let self else { return }
                if let revert { self.blocks = NotionBlock.replacing(revert.id, with: revert, in: self.blocks) }
                self.error = (error as? NotionAPIError ?? .network).message
            }
            self?.saving.remove(key)
        }
    }
}

struct NotionDueLabel: View {
    let due: NotionDate
    let now: Date
    let size: Double
    var body: some View {
        let overdue = due.isOverdue(now: now)
        let text = due.date().map { date in
            due.hasTime ? date.formatted(.dateTime.month().day().weekday().hour().minute()) : date.formatted(.dateTime.month().day().weekday())
        } ?? due.start
        Label(text, systemImage: "calendar")
            .font(.system(size: size, weight: overdue ? .semibold : .regular)).labelStyle(.titleAndIcon)
            .foregroundStyle(overdue ? ScrimPalette.red : Color.secondary)
            .accessibilityLabel(overdue ? "期限切れ " + text : "期限 " + text)
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if next > width && !current.items.isEmpty { rows.append(current); current = ([index], size.width, size.height) }
            else { current = (current.items + [index], next, max(current.height, size.height)) }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

struct FilterChip: View {
    @Environment(\.scrimAccent) private var accent
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? accent.button : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Saved filters: due date, one status/select/multi-select column, and assignees.
struct NotionTaskFiltersView: View {
    @ObservedObject var model: NotionTasksModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("絞り込み").font(.headline)
                Spacer()
                Button("解除") { model.clearFilters() }.controlSize(.small).disabled(!model.filter.isActive)
                Button("完了") { model.showingFilters = false }.buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    section("期限") {
                        FlowLayout {
                            ForEach(NotionTaskFilter.Due.allCases, id: \.self) { due in
                                FilterChip(title: due.title, selected: model.filter.due == due) { model.filter.due = due }
                            }
                        }
                    }
                    ForEach(model.filterProperties) { property in
                        section(property.name) {
                            FlowLayout {
                                ForEach(model.filterOptions(property)) { option in
                                    FilterChip(title: option.name, selected: model.filter.choiceProperty == property.id && model.filter.choiceValues.contains(option.id)) {
                                        model.toggleChoice(option.id, of: property.id)
                                    }
                                }
                            }
                        }
                    }
                    section("担当者") {
                        if model.mapping?.assigneeProperty == nil {
                            Text("「データベースと列を設定」で担当者の列を選ぶと使えます。").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else if model.knownPeople.isEmpty {
                            Text("担当者が設定されたタスクはありません。").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            FlowLayout {
                                ForEach(model.knownPeople) { person in
                                    FilterChip(title: person.name.isEmpty ? "名前なし" : person.name, selected: model.filter.people.contains(person.id)) {
                                        model.togglePerson(person.id)
                                    }
                                }
                            }
                        }
                    }
                    if model.filterProperties.count > 1 {
                        Text("ステータス・タグの絞り込みは1つの列で行います。別の列の値を選ぶと切り替わります。")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

/// An opened task: title, due date, status, assignees and tags, then its page content.
struct NotionTaskDetailView: View {
    @Environment(\.scrimAccent) private var accent
    @ObservedObject var model: NotionTaskDetailModel
    let now: Date
    let close: () -> Void
    @ObservedObject private var appearance = PanelTextAppearance.shared
    @State private var newText = ""
    @State private var newKind: NotionBlock.Kind = .paragraph
    @FocusState private var focus: Field?
    enum Field: Hashable { case title, block, add }
    private var size: PanelTextSize { appearance.notionSize }
    static let labelWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: close) { Label("一覧", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                if model.loading || !model.saving.isEmpty { ProgressView().controlSize(.small) }
                Button { model.openInNotion() } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless).help("Notionで開く").disabled(model.task.url == nil)
                Button("完了にする") { model.onComplete?(model.task) }.controlSize(.small)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    titleRow
                    properties
                    if let error = model.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(ScrimPalette.red).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    content
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            addBlockRow
        }
    }

    @ViewBuilder private var titleRow: some View {
        if model.editingTitle {
            TextField("タスク名", text: $model.titleDraft).textFieldStyle(.roundedBorder)
                .font(.system(size: size.task + 3, weight: .semibold)).focused($focus, equals: .title)
                .onSubmit { model.saveTitle() }
                .onAppear { focus = .title }
        } else {
            Text(model.task.title.isEmpty ? "無題" : model.task.title)
                .font(.system(size: size.task + 3, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle()).onTapGesture { model.beginTitleEdit() }
                .help("クリックで名前を変更")
                .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder private var properties: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.mapping.dueProperty != nil {
                HStack(spacing: 8) {
                    Text("期限").font(.system(size: size.detail, weight: .semibold)).foregroundStyle(.secondary).frame(width: Self.labelWidth, alignment: .leading)
                    if let due = model.task.due {
                        NotionDueLabel(due: due, now: now, size: size.detail + 1)
                        DatePicker("期限", selection: Binding(get: { due.date() ?? now }, set: { model.setDue($0) }), displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field).controlSize(.small)
                        Button { model.setDue(nil) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("期限を外す")
                    } else {
                        Button { model.setDue(Calendar.current.startOfDay(for: now)) } label: { Label("期限を設定", systemImage: "calendar.badge.plus") }
                            .buttonStyle(.borderless).controlSize(.small)
                    }
                }
            }
            if let status = model.statusProperty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(status.name).font(.system(size: size.detail, weight: .semibold)).foregroundStyle(.secondary).frame(width: Self.labelWidth, alignment: .leading)
                    FlowLayout {
                        ForEach(status.options) { option in
                            FilterChip(title: option.name, selected: model.task.statusOptionID == option.id) { model.setStatus(option.id) }
                        }
                    }
                }
            }
            if !model.assignees.isEmpty {
                propertyLine("担当", model.assignees.joined(separator: "・"))
            }
            ForEach(model.tags, id: \.property) { tag in propertyLine(tag.property, tag.values.joined(separator: "・")) }
        }
    }
    private func propertyLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: size.detail, weight: .semibold)).foregroundStyle(.secondary).frame(width: Self.labelWidth, alignment: .leading).lineLimit(1)
            Text(value).font(.system(size: size.detail + 1)).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        if !model.loaded && model.loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 60)
        } else if model.loaded && model.blocks.isEmpty {
            Text("本文はありません").font(.system(size: size.body)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, block in
                    blockView(block, number: listNumber(index, in: model.blocks), depth: 0)
                }
                if model.truncated {
                    Text("長いページのため、一部だけ表示しています。続きはNotionで開いてください。")
                        .font(.system(size: size.detail)).foregroundStyle(.secondary)
                }
            }
        }
    }
    /// Position within a run of numbered list items.
    private func listNumber(_ index: Int, in blocks: [NotionBlock]) -> Int {
        var number = 1, i = index - 1
        while i >= 0, blocks[i].kind == .numbered { number += 1; i -= 1 }
        return number
    }

    private func blockView(_ block: NotionBlock, number: Int, depth: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 4) {
            if model.editingBlock == block.id { editor(block) } else { line(block, number: number) }
            if !block.children.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(block.children.enumerated()), id: \.element.id) { index, child in
                        blockView(child, number: listNumber(index, in: block.children), depth: depth + 1)
                    }
                }.padding(.leading, 18)
            } else if block.hasChildren && block.kind.loadsChildren {
                Text("…").font(.system(size: size.detail)).foregroundStyle(.secondary).padding(.leading, 18)
            }
        })
    }

    @ViewBuilder private func line(_ block: NotionBlock, number: Int) -> some View {
        let body = size.body
        switch block.kind {
        case .paragraph:
            editable(block) { richText(block, size: body) }
        case .heading(let level):
            editable(block) { richText(block, size: body + Double(max(1, 5 - level) * 2), weight: .bold) }
        case .bulleted:
            editable(block) { HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").font(.system(size: body)); richText(block, size: body) } }
        case .numbered:
            editable(block) { HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(number).").font(.system(size: body)).monospacedDigit(); richText(block, size: body) } }
        case .todo:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { model.toggleChecked(block) } label: {
                    Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(block.checked ? accent.ink : Color.secondary).font(.system(size: body))
                }
                .buttonStyle(.plain).disabled(model.saving.contains(block.id))
                .accessibilityLabel(block.checked ? "チェック済み" : "未チェック")
                editable(block) { richText(block, size: body).strikethrough(block.checked).foregroundStyle(block.checked ? .secondary : .primary) }
            }
        case .toggle:
            editable(block) { HStack(alignment: .firstTextBaseline, spacing: 6) { Image(systemName: "chevron.down").font(.system(size: body - 4)).foregroundStyle(.secondary); richText(block, size: body) } }
        case .quote:
            editable(block) {
                richText(block, size: body).padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 3) }
            }
        case .callout:
            editable(block) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { Text(block.icon ?? "💡"); richText(block, size: body) }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        case .code:
            editable(block) {
                Text(block.plainText).font(.system(size: body - 1, design: .monospaced)).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
        case .divider:
            Divider()
        case .image:
            if let url = block.url {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Color.primary.opacity(0.05) }
                    .frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case .bookmark:
            if let url = block.url {
                Button { model.onOpenPage?(url) } label: { Label(url.host ?? url.absoluteString, systemImage: "link").font(.system(size: body)) }
                    .buttonStyle(.borderless)
            }
        case .childPage, .childDatabase:
            Label(block.label.isEmpty ? "無題" : block.label, systemImage: block.kind == .childPage ? "doc.text" : "tablecells")
                .font(.system(size: body)).foregroundStyle(.secondary)
        default:
            readOnlyPlaceholder
        }
    }
    private var readOnlyPlaceholder: some View {
        Label("このブロックはNotionで表示してください", systemImage: "rectangle.dashed")
            .font(.system(size: size.detail)).foregroundStyle(.secondary)
    }
    private func richText(_ block: NotionBlock, size: Double, weight: Font.Weight = .regular) -> Text {
        var result = AttributedString()
        for run in block.text {
            var piece = AttributedString(run.text)
            var font = Font.system(size: size, weight: run.bold ? .bold : weight, design: run.code ? .monospaced : .default)
            if run.italic { font = font.italic() }
            piece.font = font
            if run.strikethrough { piece.strikethroughStyle = .single }
            if run.underline { piece.underlineStyle = .single }
            if let href = run.href, let url = URL(string: href) { piece.link = url }
            result += piece
        }
        if block.text.isEmpty { result = AttributedString(" "); result.font = .system(size: size) }
        return Text(result)
    }
    /// Editable blocks open an editor on click; formatted ones only show a lock hint.
    private func editable<Content: View>(_ block: NotionBlock, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            content().fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !block.isEditable && block.kind.holdsText {
                Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(.tertiary)
                    .help("書式やリンクを含むため、Notionで編集してください")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if block.isEditable { model.beginEdit(block); focus = .block } }
    }

    private func editor(_ block: NotionBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("本文", text: $model.blockDraft, axis: .vertical).textFieldStyle(.roundedBorder)
                .font(.system(size: size.body)).lineLimit(1...12).focused($focus, equals: .block)
                .onSubmit { model.saveBlock() }
            HStack(spacing: 8) {
                Button(model.confirmingDelete == block.id ? "本当に削除" : "削除", role: .destructive) { model.delete(block) }
                    .controlSize(.small)
                Spacer()
                Button("キャンセル") { model.cancelEdit() }.controlSize(.small)
                Button("保存") { model.saveBlock() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var addBlockRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("種類", selection: $newKind) {
                Text("段落").tag(NotionBlock.Kind.paragraph)
                Text("ToDo").tag(NotionBlock.Kind.todo)
                Text("箇条書き").tag(NotionBlock.Kind.bulleted)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(maxWidth: 240)
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("本文に追加", text: $newText).textFieldStyle(.plain).font(.system(size: size.body))
                    .focused($focus, equals: .add)
                    .onSubmit { model.append(newText, kind: newKind); newText = ""; focus = .add }
                if model.saving.contains("append") { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .disabled(!model.loaded)
    }
}
