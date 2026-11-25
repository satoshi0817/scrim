import AppKit
import SwiftUI
import ScrimCore

extension Notification.Name {
    static let meetingBadgeChanged = Notification.Name("ScrimMeetingBadgeChanged")
}

@MainActor final class MeetingNotchBadge: NSObject {
    private let store: SettingsStore
    private var sources: [URL: UpcomingEventsModel] = [:]
    private var lastFetch = Date.distantPast
    private var timer: Timer?
    private var lastBadge: NotchWings?
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private static let hiddenKey = "notchHiddenOccurrences"

    init(store: SettingsStore) {
        self.store = store
        super.init()
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        NotificationCenter.default.addObserver(self, selector: #selector(updateBadge), name: .meetingBadgeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateBadge), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateBadge() }
        }
        updateBadge()
    }
    static func isHidden(_ event: UpcomingEvent, occurrences: [String: Any]?, now: Date) -> Bool {
        (occurrences?[event.id] as? Double ?? 0) > now.timeIntervalSince1970
    }
    static func isHidden(_ event: UpcomingEvent) -> Bool {
        isHidden(event, occurrences: UserDefaults.standard.dictionary(forKey: hiddenKey), now: Date())
    }
    static func toggleHidden(_ event: UpcomingEvent) {
        var hidden = UserDefaults.standard.dictionary(forKey: hiddenKey) as? [String: Double] ?? [:]
        hidden = hidden.filter { $0.value > Date().timeIntervalSince1970 }
        if hidden.removeValue(forKey: event.id) == nil { hidden[event.id] = event.end.timeIntervalSince1970 }
        UserDefaults.standard.set(hidden, forKey: hiddenKey)
        NotificationCenter.default.post(name: .meetingBadgeChanged, object: nil)
    }
    static func candidate(_ events: some Sequence<UpcomingEvent>, now: Date, lead: Int, limit: Int, onlineOnly: Bool) -> UpcomingEvent? {
        events.lazy.filter {
            $0.attendance == .accepted && !$0.allDay && $0.end > now && $0.end > $0.start &&
            $0.start.timeIntervalSince(now) <= Double(lead) * 60 &&
            $0.end.timeIntervalSince($0.start) < Double(limit) * 3600 &&
            (!onlineOnly || $0.hasMeetingLink)
        }.min {
            let ongoing = $0.start <= now, otherOngoing = $1.start <= now
            if ongoing != otherOngoing { return ongoing }
            let a = ongoing ? $0.end : $0.start, b = otherOngoing ? $1.end : $1.start
            return a == b ? $0.id < $1.id : a < b
        }
    }
    @objc private func updateBadge() {
        guard store.notchMeetingsEnabled, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopRightArea != nil }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            sources.removeAll(); panel.orderOut(nil); return
        }
        // Independent of per-display visibility: the badge has its own switch.
        let panels = store.panelsAcrossPages()
        let urls = Set(panels.lazy.map(\.url).filter { WidgetSpec(url: $0)?.kind == .upcoming })
        sources = sources.filter { urls.contains($0.key) }
        let now = Date()
        for url in urls {
            if let model = sources[url] {
                if now.timeIntervalSince(lastFetch) >= 60 { model.refresh(now: now) }
            } else if let spec = WidgetSpec(url: url) {
                let model = UpcomingEventsModel(selectedCalendarIDs: spec.calendarIDs, displayDays: spec.agendaDays, excludedKeywords: spec.excludedKeywords)
                model.setActive(true)
                sources[url] = model
            }
        }
        if now.timeIntervalSince(lastFetch) >= 60 { lastFetch = now }
        let hidden = UserDefaults.standard.dictionary(forKey: Self.hiddenKey)
        let events = sources.values.lazy.flatMap(\.events).filter { !Self.isHidden($0, occurrences: hidden, now: Date()) }
        guard let event = Self.candidate(events, now: now, lead: store.notchLeadMinutes, limit: store.notchLimitHours, onlineOnly: store.notchOnlineOnly) else { panel.orderOut(nil); return }
        let ongoing = event.start <= now
        let seconds = (ongoing ? event.end : event.start).timeIntervalSince(now)
        let meetingURL = event.meetingLinks.first(where: { $0.meetingService != nil && EventLinks.isWebURL($0.url) })?.url
        panel.ignoresMouseEvents = meetingURL == nil
        let badge = NotchWings(meetingURL: meetingURL, endsAt: event.end, ongoing: ongoing, seconds: Int(ceil(seconds)), notchWidth: right.minX - left.maxX)
        let frame = NSRect(x: left.maxX - badge.wingWidth, y: screen.frame.maxY - screen.safeAreaInsets.top,
                           width: badge.notchWidth + 2 * badge.wingWidth, height: screen.safeAreaInsets.top)
        if lastBadge != badge {
            if let host = panel.contentView as? NSHostingView<NotchWings> { host.rootView = badge }
            else { panel.contentView = NotchHostingView(rootView: badge) }
            lastBadge = badge
        }
        panel.sharingType = store.hideFromScreenCapture ? .none : .readOnly
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    deinit { timer?.invalidate() }
}

private final class NotchHostingView: NSHostingView<NotchWings> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct NotchWings: View, Equatable {
    let meetingURL: URL?
    let endsAt: Date
    let ongoing: Bool
    let seconds: Int
    let notchWidth: CGFloat
    let wingWidth: CGFloat = 52
    private var minutes: Int { (seconds + 59) / 60 }
    private var tint: Color {
        if seconds < 300 {
            return ScrimPalette.mix(ScrimPalette.nativeRed, ScrimPalette.nativeAmber, CGFloat(seconds) / 300)
        }
        return ScrimPalette.mix(ScrimPalette.nativeAmber, ScrimPalette.nativeBlue, CGFloat(seconds - 300) / 300)
    }
    var body: some View {
        HStack(spacing: 0) {
            wing { Image(systemName: ongoing ? "timer" : "calendar") }
            Color.clear.frame(width: notchWidth)
            wing { Text("\(minutes)分").monospacedDigit().lineLimit(1).minimumScaleFactor(0.8) }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(tint)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
    }
    @ViewBuilder private func wing<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let label = content().frame(width: wingWidth).frame(maxHeight: .infinity).contentShape(Rectangle())
        let time = (ongoing ? "終了まで" : "開始まで") + "\(minutes)分"
        if let meetingURL {
            let action = (MeetingLink.service(for: meetingURL) ?? "会議") + "に参加"
            Button {
                if Date() < endsAt { DefaultBrowser.open(meetingURL) }
            } label: { label }
            .buttonStyle(.plain)
            .help(action)
            .accessibilityLabel(time + "、" + action)
        } else {
            label.accessibilityLabel(time)
        }
    }
}

struct NotchSettingsPreview: View {
    @State private var ongoing = false
    @State private var minutes = 5.0
    var body: some View {
        DisclosureGroup("表示を試す") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer(minLength: 0)
                    NotchWings(meetingURL: nil, endsAt: .distantFuture, ongoing: ongoing,
                               seconds: Int(minutes) * 60, notchWidth: 108)
                        .frame(width: 212, height: 30)
                    Spacer(minLength: 0)
                }
                .frame(height: 54, alignment: .top)
                .background(ScrimPalette.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                Picker("予定の状態", selection: $ongoing) {
                    Text("開始前").tag(false)
                    Text("進行中").tag(true)
                }.pickerStyle(.segmented)
                HStack {
                    Text(ongoing ? "終了まで" : "開始まで").font(.caption)
                    Slider(value: $minutes, in: 1...15, step: 1)
                        .accessibilityLabel("プレビューの残り時間")
                        .accessibilityValue("\(Int(minutes))分")
                    Text("\(Int(minutes))分").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }.padding(.vertical, 6)
        }
    }
}
