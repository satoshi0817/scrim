import AppKit
import EventKit
import SwiftUI
import ScrimCore

enum AgendaAttendance: String, CaseIterable {
    case accepted = "承諾済み", pending = "未回答", tentative = "仮承諾", declined = "辞退", delegated = "代理を依頼", organizer = "主催", unknown = "出欠情報なし"
    init(event: EKEvent) {
        if let me = event.attendees?.first(where: { $0.isCurrentUser }) {
            switch me.participantStatus {
            case .accepted: self = .accepted
            case .pending: self = .pending
            case .tentative: self = .tentative
            case .declined: self = .declined
            case .delegated: self = .delegated
            default: self = event.organizer?.isCurrentUser == true ? .organizer : .unknown
            }
        } else {
            self = event.organizer?.isCurrentUser == true ? .organizer : .unknown
        }
    }
}

struct UpcomingEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let color: NSColor
    var attendance: AgendaAttendance = .unknown
    var calendarID: String = ""
    var meetingURL: URL? = nil
    var links: [EventLink] = []
    var notes: String? = nil
    var meetingLinks: [EventLink] {
        var result = links.filter { $0.meetingService != nil }
        if let meetingURL, !result.contains(where: { $0.url == meetingURL }) { result.insert(EventLink(url: meetingURL), at: 0) }
        return result
    }
    var otherLinks: [EventLink] { links.filter { $0.meetingService == nil } }
}

struct ExcludedKeywordRow: Identifiable {
    let id = UUID()
    var text: String
}

struct CalendarOption: Identifiable {
    let id: String
    let title: String
    let accountID: String
    let accountTitle: String
    let color: NSColor
}

struct AgendaDay: Identifiable {
    let date: Date
    var events: [UpcomingEvent]
    var id: Date { date }
}

enum AgendaPresentation {
    static func currentEvent(_ events: [UpcomingEvent], now: Date) -> UpcomingEvent? {
        events.filter { !$0.allDay && $0.end > now }.sorted {
            if ($0.start <= now) != ($1.start <= now) { return $0.start <= now }
            return $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }.first
    }
    static func nextAcceptedEvent(_ events: [UpcomingEvent], now: Date) -> UpcomingEvent? {
        events.filter { !$0.allDay && $0.start > now && $0.attendance == .accepted }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }.first
    }
    static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "あと\(minutes)分" }
        let days = minutes / 1440, hours = (minutes % 1440) / 60, remainder = minutes % 60
        if days > 0 { return "あと\(days)日" + (hours > 0 ? "\(hours)時間" : "") }
        return "あと\(hours)時間" + (remainder > 0 ? "\(remainder)分" : "")
    }
    static func minutesUntilStart(_ event: UpcomingEvent, now: Date) -> Int? {
        let seconds = event.start.timeIntervalSince(now)
        guard !event.allDay, event.end > now, seconds > 0, seconds < 3600 else { return nil }
        return max(1, Int(ceil(seconds / 60)))
    }
    static func groups(_ events: [UpcomingEvent], now: Date, calendar: Calendar = .current) -> [AgendaDay] {
        let today = calendar.startOfDay(for: now)
        var days: [Date: [UpcomingEvent]] = [today: []]
        for event in events { days[max(today, calendar.startOfDay(for: event.start)), default: []].append(event) }
        return days.keys.sorted().map { date in
            let sorted = days[date]!.sorted { a, b in
                if a.allDay != b.allDay { return a.allDay }
                return a.start == b.start ? a.title < b.title : a.start < b.start
            }
            return AgendaDay(date: date, events: sorted)
        }
    }
}

@MainActor final class UpcomingEventsModel: ObservableObject {
    @Published private(set) var events: [UpcomingEvent] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var requesting = false
    @Published private(set) var error: String?
    @Published private(set) var calendars: [CalendarOption] = []
    @Published private(set) var selectedCalendarIDs: Set<String>?
    @Published private(set) var displayDays: Int
    @Published private(set) var keywordRows: [ExcludedKeywordRow]
    var excludedKeywords: [String] { EventExclusion.normalized(keywordRows.map(\.text)) }
    @Published var isConfiguring = false
    @Published private(set) var presentationRevision = 0
    var onOpenLink: ((URL) -> Void)?
    var onOpenMeeting: ((URL) -> Void)?
    var onConfigurationChange: (() -> Void)?
    var onSelectionChange: ((Set<String>?) -> Void)?
    private var allEvents: [UpcomingEvent] = []
    private let fixtureEvents: [UpcomingEvent]?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var active = false
    // Verification does not read personal calendars or request permission.
    private let isolated = CommandLine.arguments.contains { $0.hasPrefix("--verify-") || $0.hasSuffix("-review") }
    init(selectedCalendarIDs: Set<String>? = nil, displayDays: Int = 7, excludedKeywords: [String] = [], previewEvents: [UpcomingEvent]? = nil, previewCalendars: [CalendarOption] = []) {
        self.selectedCalendarIDs = selectedCalendarIDs; self.displayDays = min(31, max(1, displayDays)); fixtureEvents = previewEvents
        keywordRows = EventExclusion.normalized(excludedKeywords).map { ExcludedKeywordRow(text: $0) }
        calendars = previewCalendars
        if let previewEvents {
            allEvents = previewEvents.filter { selectedCalendarIDs?.contains($0.calendarID) ?? true }
            events = allEvents.filter { !EventExclusion.matches(title: $0.title, keywords: excludedKeywords) }; status = .fullAccess
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func setActive(_ value: Bool) { active = value; if value { refresh() } }
    func beginPresentation(resetScroll: Bool) { if resetScroll { presentationRevision += 1 } }
    func openLink(_ url: URL) { guard EventLinks.isWebURL(url) else { return }; onOpenLink?(url) }
    func openMeeting(_ url: URL) {
        guard MeetingLink.service(for: url) != nil else { return }
        onOpenMeeting?(url)
    }
    func isSelected(_ id: String) -> Bool { selectedCalendarIDs?.contains(id) ?? true }
    func select(_ ids: Set<String>?) {
        selectedCalendarIDs = ids; onSelectionChange?(ids); onConfigurationChange?(); refresh()
    }
    @discardableResult func addExcludedKeyword() -> UUID {
        let row = ExcludedKeywordRow(text: ""); keywordRows.append(row); return row.id
    }
    func editExcludedKeyword(_ id: UUID, text: String) {
        guard let index = keywordRows.firstIndex(where: { $0.id == id }) else { return }
        keywordRows[index].text = text; onConfigurationChange?(); applyExclusions()
    }
    func removeExcludedKeyword(_ id: UUID) {
        keywordRows.removeAll { $0.id == id }; onConfigurationChange?(); applyExclusions()
    }
    func setDisplayDays(_ value: Int) { displayDays = min(31, max(1, value)); onConfigurationChange?(); refresh() }
    func setSelected(_ ids: [String], enabled: Bool) {
        var selection = selectedCalendarIDs ?? Set(calendars.map(\.id))
        if enabled { selection.formUnion(ids) } else { selection.subtract(ids) }
        select(selection)
    }
    private func applyExclusions() {
        let keywords = excludedKeywords
        events = allEvents.filter { !EventExclusion.matches(title: $0.title, keywords: keywords) }
    }
    func refresh(now: Date = Date()) {
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: displayDays, to: start)!
        if let fixtureEvents {
            allEvents = fixtureEvents.filter { isSelected($0.calendarID) && $0.start < end && $0.end > start }
            applyExclusions(); status = .fullAccess; return
        }
        guard !isolated else { status = .notDetermined; allEvents = []; events = []; calendars = []; return }
        status = EKEventStore.authorizationStatus(for: .event)
        guard active, status == .fullAccess else { allEvents = []; events = []; if status != .fullAccess { calendars = [] }; return }
        let available = store.calendars(for: .event)
        calendars = available.map { calendar in
            CalendarOption(id: calendar.calendarIdentifier, title: calendar.title,
                           accountID: calendar.source.sourceIdentifier, accountTitle: calendar.source.title,
                           color: calendar.cgColor.flatMap(NSColor.init(cgColor:)) ?? ScrimPalette.nativeBlue)
        }.sorted { ($0.accountTitle, $0.title, $0.id) < ($1.accountTitle, $1.title, $1.id) }
        let selected = available.filter { isSelected($0.calendarIdentifier) }
        // Passing an empty array to EventKit can mean "all"; never query in that case.
        guard !selected.isEmpty else { allEvents = []; events = []; return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        allEvents = store.events(matching: predicate)
            .filter { $0.endDate > start && $0.startDate < end && $0.status != .canceled }
            .sorted { $0.startDate == $1.startDate ? ($0.title ?? "") < ($1.title ?? "") : $0.startDate < $1.startDate }
            .map { event in
                UpcomingEvent(id: event.calendar.calendarIdentifier + ":" + (event.eventIdentifier ?? event.calendarItemIdentifier) + ":" + String(event.startDate.timeIntervalSince1970), title: event.title ?? "名称未設定", start: event.startDate,
                              end: event.endDate, allDay: event.isAllDay, location: event.location,
                              color: event.calendar.cgColor.flatMap(NSColor.init(cgColor:)) ?? ScrimPalette.nativeBlue, attendance: AgendaAttendance(event: event), calendarID: event.calendar.calendarIdentifier,
                              meetingURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]),
                              links: EventLinks.extract(in: [event.url?.absoluteString, event.location, event.notes]), notes: EventLinks.notes(event.notes))
            }
        applyExclusions()
    }
    func requestAccess() {
        guard !isolated, !requesting else { return }
        requesting = true; error = nil
        Task {
            do { _ = try await store.requestFullAccessToEvents() }
            catch { self.error = "カレンダーに接続できませんでした。もう一度お試しください。" }
            requesting = false; refresh()
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

struct UpcomingEventsView: View {
    @ObservedObject var model: UpcomingEventsModel
    let now: Date
    let size: CGSize
    var editing = false
    @State private var expandedEvents: Set<String> = []
    @FocusState private var focusedKeyword: UUID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var compact: Bool { size.width < 300 || size.height < 260 }
    var body: some View {
        ZStack {
            front
                .modifier(CalendarCardFace(hidden: model.isConfiguring ? 1 : 0, motion: !reduceMotion))
                .allowsHitTesting(!model.isConfiguring)
                .accessibilityHidden(model.isConfiguring)
            configuration
                .modifier(CalendarCardFace(hidden: model.isConfiguring ? 0 : 1, motion: !reduceMotion))
                .allowsHitTesting(model.isConfiguring)
                .accessibilityHidden(!model.isConfiguring)
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.22), value: model.isConfiguring)
    }
    private var front: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    Text("次の予定").font(.system(size: compact ? 16 : 18, weight: .semibold))
                }
                Spacer(minLength: 4)
                Text("\(model.displayDays)日間 · \(model.events.count)件")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
            if model.status == .fullAccess {
                if model.events.isEmpty {
                    Spacer(minLength: 0)
                    Text(model.selectedCalendarIDs?.isEmpty == true ? "表示するカレンダーを設定から選択してください" : "選択したカレンダーに\(model.displayDays)日間の予定はありません").font(.system(size: 15)).foregroundStyle(.secondary)
                } else {
                    let featuredID = AgendaPresentation.currentEvent(model.events.filter { !$0.meetingLinks.isEmpty }, now: now)?.id
                    if let event = AgendaPresentation.nextAcceptedEvent(model.events, now: now) {
                        nextEventSummary(event, showsJoin: event.id == featuredID)
                    }
                    ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        agendaNavigation("今日", symbol: "calendar") { proxy.scrollTo("agenda-top", anchor: .top) }
                        if let current = AgendaPresentation.currentEvent(model.events, now: now) {
                            agendaNavigation("今の時間帯", symbol: "location.fill") { proxy.scrollTo(current.id, anchor: .top) }
                        }
                        Spacer(minLength: 0)
                    }
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Color.clear.frame(height: 1).id("agenda-top")
                            ForEach(AgendaPresentation.groups(model.events, now: now)) { day in
                                Section {
                                    if day.events.isEmpty {
                                        Text("今日の予定はありません").font(.callout).foregroundStyle(.secondary).padding(.bottom, 4)
                                    } else {
                                        ForEach(day.events) { event in eventRow(event, featured: event.id == featuredID).id(event.id) }
                                    }
                                } header: {
                                    HStack(alignment: .firstTextBaseline) {
                                        if Calendar.current.isDate(day.date, inSameDayAs: now) {
                                            Circle().fill(ScrimPalette.red).frame(width: 5, height: 5).offset(y: -3)
                                        }
                                        Text(dayTitle(day.date)).font(.system(size: 13, weight: .semibold))
                                        Spacer(minLength: 4)
                                        Text(day.date.formatted(.dateTime.month().day().weekday())).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 12).padding(.bottom, 8)
                                    .background(Color(nsColor: .windowBackgroundColor))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                        .background(AgendaScrollStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
                    .onChange(of: model.presentationRevision) {
                        if let current = AgendaPresentation.currentEvent(model.events, now: now) { proxy.scrollTo(current.id, anchor: .top) }
                        else { proxy.scrollTo("agenda-top", anchor: .top) }
                    }
                    .onAppear {
                        if model.presentationRevision > 0, let current = AgendaPresentation.currentEvent(model.events, now: now) {
                            proxy.scrollTo(current.id, anchor: .top)
                        }
                    }
                    }
                }
            } else {
                Text(model.status == .notDetermined ? "カレンダーの予定をここに表示" : "カレンダーへのアクセスが必要です")
                    .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                if (model.status == .notDetermined || model.status == .writeOnly) {
                    Button(model.requesting ? "接続中…" : "カレンダーを接続") { model.requestAccess() }
                        .buttonStyle(.bordered).disabled(model.requesting)
                } else {
                    Button("システム設定を開く") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }.buttonStyle(.bordered)
                }
            }
            if model.status != .fullAccess || model.events.isEmpty { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(compact ? 16 : 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("表示する予定").font(.headline)
                Spacer(minLength: 0)
                Button("完了") { focusedKeyword = nil; model.isConfiguring = false }.buttonStyle(.borderedProminent).controlSize(.small)
            }.padding(.trailing, 32).frame(height: 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Stepper(value: Binding(get: { model.displayDays }, set: model.setDisplayDays), in: 1...31) {
                            Text("表示期間：\(model.displayDays)日間").font(.callout)
                        }
                        Text("今日を含めた日数").font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("除外キーワード").font(.system(size: 13, weight: .semibold))
                        Text("予定名にどれかが含まれる予定を非表示にします。大文字・小文字は区別しません。")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(model.keywordRows) { row in
                            HStack(spacing: 6) {
                                TextField("キーワード", text: Binding(get: { model.keywordRows.first(where: { $0.id == row.id })?.text ?? "" },
                                                                     set: { model.editExcludedKeyword(row.id, text: $0) }))
                                    .textFieldStyle(.roundedBorder).focused($focusedKeyword, equals: row.id)
                                Button { model.removeExcludedKeyword(row.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).help("このキーワードを削除")
                                    .accessibilityLabel("キーワードを削除")
                            }
                        }
                        Button { focusedKeyword = model.addExcludedKeyword() } label: { Label("キーワードを追加", systemImage: "plus") }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    Divider()
                    Text("アカウント・カレンダーを選択").font(.caption).foregroundStyle(.secondary)
                    if model.status == .fullAccess {
                        HStack {
                            Button("すべて") { model.select(nil) }
                            Button("選択を解除") { model.select([]) }
                        }.buttonStyle(.borderless).font(.caption)
                        if model.calendars.isEmpty {
                            Text("利用できるカレンダーがありません").font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(accountIDs, id: \.self) { accountID in
                                let options = model.calendars.filter { $0.accountID == accountID }
                                let ids = options.map(\.id)
                                VStack(alignment: .leading, spacing: 9) {
                                    Toggle(isOn: Binding(get: { ids.allSatisfy(model.isSelected) }, set: { model.setSelected(ids, enabled: $0) })) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(options.first?.accountTitle ?? "カレンダー").font(.system(size: 13, weight: .semibold))
                                            Text("\(ids.filter(model.isSelected).count) / \(ids.count)個を表示").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }.toggleStyle(.switch)
                                    ForEach(options) { option in
                                        Toggle(isOn: Binding(get: { model.isSelected(option.id) }, set: { model.setSelected([option.id], enabled: $0) })) {
                                            HStack(spacing: 6) {
                                                Circle().fill(Color(nsColor: option.color)).frame(width: 7, height: 7)
                                                Text(option.title).font(.system(size: 12)).lineLimit(2)
                                            }
                                        }.toggleStyle(.switch).controlSize(.small).padding(.leading, 12)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("予定の表示面でカレンダーへのアクセスを許可してください。").font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(compact ? 16 : 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private var accountIDs: [String] {
        var seen: Set<String> = []
        return model.calendars.compactMap { seen.insert($0.accountID).inserted ? $0.accountID : nil }
    }
    private func agendaNavigation(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.055)))
                .contentShape(Capsule())
        }.buttonStyle(.plain).modifier(HandCursor())
    }
    private func countdownTint(_ event: UpcomingEvent) -> Color {
        guard let minutes = AgendaPresentation.minutesUntilStart(event, now: now), minutes <= 30 else { return .clear }
        let progress = Double(30 - minutes) / 29
        return ScrimPalette.mix(ScrimPalette.nativeAmber, ScrimPalette.nativeRed, progress)
            .opacity(0.05 + 0.20 * progress)
    }

    private func nextEventSummary(_ event: UpcomingEvent, showsJoin: Bool) -> some View {
        let imminent = event.start.timeIntervalSince(now) <= 900
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("次の予定 · " + AgendaPresentation.countdown(to: event.start, now: now))
                    .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.primary)
                Text(event.title).font(.system(size: compact ? 13 : 14, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsJoin, imminent, let link = event.meetingLinks.first {
                Button { model.openMeeting(link.url) } label: {
                    Label("参加", systemImage: "video.fill").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(ScrimPalette.button))
                }.buttonStyle(.plain).modifier(HandCursor()).help((link.meetingService ?? "会議") + "を外部ブラウザで開く")
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(ScrimPalette.blue.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 13).fill(countdownTint(event))))
    }
    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "今日の予定" }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!) { return "明日の予定" }
        return date.formatted(.dateTime.month().day()) + "の予定"
    }
    @ViewBuilder private func attendanceBadge(_ status: AgendaAttendance) -> some View {
        if status == .accepted || status == .pending {
            let accepted = status == .accepted
            let ink = ScrimPalette.badge(accepted: accepted, dark: colorScheme == .dark)
            Label(status.rawValue, systemImage: accepted ? "checkmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(ink.opacity(colorScheme == .dark ? 0.13 : 0.09), in: Capsule())
                .fixedSize().accessibilityLabel("出欠・" + status.rawValue)
        } else {
            Text(status.rawValue).accessibilityLabel("出欠・" + status.rawValue)
        }
    }

    private func eventRow(_ event: UpcomingEvent, featured: Bool) -> some View {
        let hiddenMeetings = featured ? [] : event.meetingLinks
        let detailCount = hiddenMeetings.count + event.otherLinks.count
        let ended = event.end <= now
        let ongoing = !event.allDay && event.start <= now && event.end > now
        let minutesUntil = AgendaPresentation.minutesUntilStart(event, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(max(event.start, Calendar.current.startOfDay(for: now)).formatted(.dateTime.month().day().weekday()))
                Spacer()
                attendanceBadge(event.attendance)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                eventTimeDisplay(event)
                Spacer(minLength: 4)
                if let minutesUntil {
                    Label("あと\(minutesUntil)分", systemImage: "timer")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                } else if ongoing {
                    Label("進行中", systemImage: "circle.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(ScrimPalette.badge(accepted: true, dark: colorScheme == .dark))
                } else if ended {
                    Text("終了").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                }
            }
            Text(event.title)
                .font(.system(size: compact ? 14 : 15, weight: .medium)).lineSpacing(2).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let location = event.location, !location.isEmpty, (event.meetingURL == nil || URL(string: location) != event.meetingURL) {
                Label(location.replacingOccurrences(of: "\n", with: " · "), systemImage: "mappin")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            ForEach(featured ? event.meetingLinks : []) { link in
                AgendaLinkButton(link: link, primary: true) { model.openMeeting(link.url) }
                    .padding(.top, 2)
            }
            if detailCount > 0 || event.notes != nil {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        if !expandedEvents.insert(event.id).inserted { expandedEvents.remove(event.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expandedEvents.contains(event.id) ? 90 : 0))
                        Text("リンクとメモ").font(.system(size: 11, weight: .medium))
                        if detailCount > 0 { Text("\(detailCount)").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }.foregroundStyle(.secondary).contentShape(Rectangle())
                }.buttonStyle(.plain).modifier(HandCursor())
                .accessibilityValue(expandedEvents.contains(event.id) ? "展開中" : "折りたたみ")
                if expandedEvents.contains(event.id) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(hiddenMeetings) { link in
                            AgendaLinkButton(link: link, primary: true) { model.openMeeting(link.url) }
                        }
                        ForEach(event.otherLinks) { link in
                            AgendaLinkButton(link: link, primary: false) { model.openLink(link.url) }
                        }
                        if let notes = event.notes {
                            if detailCount > 0 { Divider().padding(.vertical, 2) }
                            Text(verbatim: notes).font(.system(size: 12)).lineSpacing(3)
                                .foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
                }
            }
        }
        .padding(compact ? 13 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: event.color).opacity(ended ? 0.05 : 0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.035 : 0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(countdownTint(event)))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(event.attendance == .accepted ? 0.09 : 0.28), style: StrokeStyle(lineWidth: 1, dash: event.attendance == .accepted ? [] : [3, 3])).allowsHitTesting(false))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.08 : 0.025), radius: 6, x: 0, y: 3)
        .contextMenu {
            if !event.allDay && !ended {
                Button(MeetingNotchBadge.isHidden(event) ? "この予定をノッチに再表示" : "この予定をノッチに表示しない") {
                    MeetingNotchBadge.toggleHidden(event)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true).opacity(ended ? 0.45 : 1)
    }
    @ViewBuilder private func eventTimeDisplay(_ event: UpcomingEvent) -> some View {
        if event.allDay {
            Text("終日").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
        } else {
            let parts = eventTime(event).components(separatedBy: "–")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.first ?? "")
                    .font(.system(size: compact ? 21 : 24, weight: .medium, design: .rounded))
                    .tracking(-0.6).foregroundStyle(.primary)
                Text("—").font(.system(size: 11, weight: .light)).foregroundStyle(.tertiary)
                Text(parts.count > 1 ? parts[1] : "")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
    }
    private func eventTime(_ event: UpcomingEvent) -> String {
        if event.allDay { return "終日" }
        let calendar = Calendar.current
        let start = calendar.isDate(event.start, inSameDayAs: max(event.start, calendar.startOfDay(for: now)))
            ? event.start.formatted(date: .omitted, time: .shortened)
            : event.start.formatted(.dateTime.month().day().hour().minute())
        let end = calendar.isDate(event.start, inSameDayAs: event.end)
            ? event.end.formatted(date: .omitted, time: .shortened)
            : event.end.formatted(.dateTime.month().day().hour().minute())
        return start + "–" + end
    }
}


/// Switches between the agenda and its settings with a soft cross-fade, matching panel menus: the outgoing
/// face fades, blurs and shrinks slightly while the other fades in. Nothing turns. Fade only with Reduce Motion.
private struct CalendarCardFace: AnimatableModifier {
    /// 0 while this face is shown, 1 while hidden.
    var hidden: Double
    var motion: Bool
    var animatableData: Double { get { hidden } set { hidden = newValue } }
    func body(content: Content) -> some View {
        content.opacity(1 - hidden)
            .scaleEffect(motion ? 1 - 0.03 * hidden : 1)
            .blur(radius: motion ? 6 * hidden : 0)
    }
}


private struct HandCursor: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.onHover(perform: update).onDisappear { update(false) }
    }
    private func update(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        if value { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}

private struct AgendaLinkButton: View {
    let link: EventLink
    let primary: Bool
    let action: () -> Void
    @State private var hovering = false
    private var tint: Color {
        ScrimPalette.button
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: primary ? 4 : 8) {
                if link.isNotion && link.host != "calendar.notion.com" {
                    Text("N").font(.system(size: 14, weight: .bold, design: .serif)).frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                } else {
                    Image(systemName: link.symbol).font(.system(size: primary ? 11 : 13, weight: .medium)).frame(width: primary ? 14 : 20)
                }
                if primary {
                    Text((link.meetingService ?? link.title) + " に参加").font(.system(size: 11, weight: .semibold))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        Text(link.host).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if !primary { Spacer(minLength: 4) }
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).opacity(primary ? 0.85 : 0.5)
            }
            .foregroundStyle(primary ? Color.white : .primary)
            .padding(.horizontal, primary ? 8 : 12).padding(.vertical, primary ? 4 : 8)
            .frame(maxWidth: primary ? nil : .infinity, alignment: .leading)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [tint.opacity(hovering ? 1 : 0.94), tint.opacity(hovering ? 0.96 : 0.82)], startPoint: .top, endPoint: .bottom))
                } else {
                    RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(hovering ? 0.09 : 0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).modifier(HandCursor()).onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(SlackLinks.desktopURL(link.url) == nil ? "外部ブラウザで開く：" + link.host : "Slackで開く")
    }
}

private struct AgendaScrollStyle: NSViewRepresentable {
    final class Indicator: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }
        override func drawKnob() {
            let slot = rect(for: .knob)
            guard slot.height > 0 else { return }
            let width = min(3, slot.width)
            let thumb = NSRect(x: slot.midX - width / 2, y: slot.minY, width: width, height: slot.height)
            NSColor.labelColor.withAlphaComponent(0.23).setFill()
            NSBezierPath(roundedRect: thumb, xRadius: width / 2, yRadius: width / 2).fill()
        }
        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    }
    final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }
        func apply() {
            guard let scroll = enclosingScrollView else { return }
            if let current = scroll.verticalScroller, !(current is Indicator) {
                scroll.verticalScroller = Indicator(frame: current.frame)
            }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.verticalScroller?.controlSize = .small
        }
    }
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.apply() }
}
