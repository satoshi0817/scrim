import AppKit
import SwiftUI
import ScrimCore

@MainActor final class WidgetModel: ObservableObject {
    let upcoming: UpcomingEventsModel
    @Published var isEditing = false
    @Published var clockStyle: ClockStyle {
        didSet { if clockStyle != oldValue { onClockStyleChange?(clockStyle) } }
    }
    var onClockStyleChange: ((ClockStyle) -> Void)?
    let spec: WidgetSpec
    @Published var digitalZones = [TimeZone.current.identifier]
    @Published var configuringWorldClock = false
    @Published var now = Date()
    @Published var monthOffset = 0
    @Published var weather: WeatherSnapshot?
    @Published var error: String?
    @Published var loading = false
    @Published private(set) var showsHourly = true
    @Published private(set) var hourly: [WeatherHour] = []
    @Published private(set) var hourlyError: String?
    private var hourlyTask: Task<Void, Never>?
    private let provider: any WeatherProviding
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var revision = 0
    @Published private(set) var active = false
    init(spec: WidgetSpec, provider: any WeatherProviding = WeatherService.shared) {
        self.spec = spec; self.provider = provider; clockStyle = spec.clockStyle
        upcoming = UpcomingEventsModel(selectedCalendarIDs: spec.calendarIDs, displayDays: spec.agendaDays, excludedKeywords: spec.excludedKeywords)
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value; timer?.invalidate(); timer = nil
        if spec.kind == .upcoming { upcoming.setActive(value) }
        if value {
            now = Date()
            if spec.kind == .weather { refresh() }
            timer = Timer.scheduledTimer(withTimeInterval: spec.kind == .clock ? 1 : 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.active else { return }; self.now = Date()
                    if self.spec.kind == .upcoming { self.upcoming.refresh(now: self.now) }
                    if self.spec.kind == .weather, self.weather.map({ Date().timeIntervalSince($0.fetchedAt) >= 600 }) ?? true { self.refresh() }
                }
            }
        } else { revision += 1; task?.cancel(); task = nil; loading = false; hourlyTask?.cancel(); hourlyTask = nil }
    }
    func setShowsHourly(_ value: Bool) {
        guard showsHourly != value else { return }
        showsHourly = value
        if !value { hourlyTask?.cancel(); hourlyTask = nil }
        else if active && spec.kind == .weather { refreshHourly(force: false) }
    }
    private func refreshHourly(force: Bool) {
        guard showsHourly, hourlyTask == nil else { return }
        hourlyTask = Task { [weak self, provider] in
            do {
                let result = try await provider.hourlyForecast(force: force)
                guard let self, !Task.isCancelled else { return }
                self.hourly = result; self.hourlyError = nil; self.hourlyTask = nil
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.hourlyError = "時間ごとの予報を取得できません"; self.hourlyTask = nil
            }
        }
    }
    func refresh(force: Bool = false) {
        now = Date()
        if spec.kind == .upcoming { upcoming.refresh(now: now) }
        if spec.kind == .weather && showsHourly { refreshHourly(force: force) }
        guard spec.kind == .weather, task == nil else { return }
        revision += 1; let token = revision
        loading = true
        task = Task { [weak self, provider] in
            guard let self else { return }
            if self.weather == nil {
                let cached = await provider.cached()
                guard token == self.revision, !Task.isCancelled else { return }
                self.weather = cached
            }
            do {
                let result = try await provider.fetch(force: force)
                if !Task.isCancelled && token == self.revision { self.weather = result; self.error = nil }
            } catch {
                if !Task.isCancelled && token == self.revision { self.error = "天気を更新できません。通信状況を確認してください。" }
            }
            if token == self.revision { self.loading = false; self.task = nil }
        }
    }
    deinit { timer?.invalidate(); task?.cancel(); hourlyTask?.cancel() }
}

final class NativeWidgetPanel: NSHostingView<WidgetPanelView> {
    let model: WidgetModel
    init(spec: WidgetSpec, provider: any WeatherProviding = WeatherService.shared) {
        model = WidgetModel(spec: spec, provider: provider)
        super.init(rootView: WidgetPanelView(model: model))
        setAccessibilityLabel(spec.title)
    }
    required init(rootView: WidgetPanelView) { fatalError() }
    required init?(coder: NSCoder) { fatalError() }
    func setActive(_ value: Bool) { model.setActive(value) }
    func reload() { model.refresh(force: true) }
    func setEditing(_ value: Bool) {
        model.isEditing = value
        if !value { model.configuringWorldClock = false; model.upcoming.isConfiguring = false }
    }
    func allowsControl(at point: NSPoint) -> Bool {
        guard model.isEditing else { return false }
        return (model.configuringWorldClock || (model.spec.kind == .upcoming && model.upcoming.isConfiguring)) && bounds.insetBy(dx: 8, dy: 8).contains(point)
    }
}

struct WidgetPanelView: View {
    @ObservedObject var model: WidgetModel
    @State private var clockPage = 0
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 260 || geometry.size.width < 300
            Group {
                switch model.spec.kind {
                case .weather: weather(compact: compact, size: geometry.size)
                case .calculator: CalculatorWidget()
                case .worldclock: WorldClockView(now: model.now, configuring: $model.configuringWorldClock)
                case .clock: clock(size: geometry.size)
                case .calendar: calendar(size: geometry.size)
                case .upcoming: UpcomingEventsView(model: model.upcoming, now: model.now, size: geometry.size, editing: model.isEditing)
                }
            }
            .padding(model.spec.kind == .upcoming ? 0 : model.spec.kind == .weather ? min(24, min(geometry.size.width, geometry.size.height) * 0.075) : compact ? 16 : 24)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func time(_ date: Date, format: String, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ja_JP"); formatter.timeZone = zone; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private func clock(size: CGSize) -> some View {
        VStack(spacing: 12) {
            if model.clockStyle == .analog {
                AnalogClockFace(now: model.now).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                digitalClock
            }
            if size.height > 200 {
                Text(time(model.now, format: "M月d日 EEEE"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.045)))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).padding(-32))
    }
    private var digitalClock: some View {
        GeometryReader { geometry in
            let zones = model.digitalZones
            let capacity = max(1, min(3, Int(geometry.size.width / 135)))
            let pages = max(1, (zones.count + capacity - 1) / capacity)
            let page = min(clockPage, pages - 1)
            let visible = zones.dropFirst(page * capacity).prefix(capacity)
            let width = max(1, geometry.size.width - (pages > 1 ? 52 : 0)) / CGFloat(max(1, visible.count))
            let font = min(96, width * (visible.count == 1 ? 0.25 : 0.30), geometry.size.height * 0.49)
            HStack(spacing: 0) {
                if pages > 1 { clockArrow("chevron.left", "前の都市") { clockPage = (page + pages - 1) % pages } }
                ForEach(visible, id: \.self) { id in
                    let city = WorkCity(id: id)
                    VStack(spacing: min(6, geometry.size.height * 0.035)) {
                        Text(city.name + " · " + city.label(model.now, format: "z"))
                            .font(.system(size: min(14, max(10, font * 0.25)), weight: .medium)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(city.label(model.now, format: "HH:mm")).font(.system(size: font, weight: .regular, design: .rounded))
                            if visible.count == 1 {
                                Text(city.label(model.now, format: "ss")).font(.system(size: font * 0.36)).foregroundStyle(.secondary)
                            }
                        }.monospacedDigit()
                    }.lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                }
                if pages > 1 { clockArrow("chevron.right", "次の都市") { clockPage = (page + 1) % pages } }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func clockArrow(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 26, height: 32).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private var localCalendar: Calendar { var value = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "ja_JP"); return value }
    private func calendar(size: CGSize) -> some View {
        let calendar = localCalendar
        let month = calendar.date(byAdding: .month, value: model.monthOffset, to: model.now)!
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        let offset = calendar.component(.weekday, from: start)-1
        let cellHeight = max(12, (size.height-148)/6)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time(start, format: "M月")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.red)
                    Text(time(model.now, format: "d")).font(.system(size: size.height < 260 ? 32 : 48, weight: .light, design: .rounded))
                }
                Spacer(minLength: 0)
                Button { model.monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.help("前の月")
                Button("今日") { model.monthOffset = 0 }.font(.caption)
                Button { model.monthOffset += 1 } label: { Image(systemName: "chevron.right") }.help("次の月")
            }.buttonStyle(.borderless)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { index, value in
                        Text(value).font(.caption).foregroundStyle(index == 0 ? Color.red : .secondary).frame(maxWidth: .infinity).frame(height: size.height < 260 ? 20 : 24)
                    }
                }
                ForEach(0..<6) { row in
                    GridRow {
                        ForEach(0..<7) { column in
                            let day = row*7+column-offset+1
                            let isToday = day > 0 && day <= count && calendar.isDate(calendar.date(byAdding: .day, value: day-1, to: start)!, inSameDayAs: model.now)
                            Text(day > 0 && day <= count ? String(day) : " ")
                                .font(.system(size: min(18, max(11, cellHeight*0.45)), weight: isToday ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(isToday ? Color.white : column == 0 ? .red : .primary)
                                .frame(maxWidth: .infinity).frame(height: cellHeight)
                                .background { if isToday { Circle().fill(Color.red).frame(width: min(32, cellHeight-1), height: min(32, cellHeight-1)) } }
                                .accessibilityLabel(day > 0 && day <= count ? "\(day)日"+(isToday ? " 今日" : "") : "")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor).padding(-32))
    }
    @ViewBuilder private func weather(compact: Bool, size: CGSize) -> some View {
        if model.showsHourly && size.width >= 275 && size.width / max(1, size.height) >= 1.7 && size.height < 320 {
            wideWeather(size: size)
        } else {
        VStack(alignment: .leading, spacing: min(10, size.height * 0.025)) {
            HStack {
                Text("東京").font(.system(size: min(22, size.height * 0.12), weight: .medium))
                Spacer()
                if model.loading { ProgressView().controlSize(.small).tint(.white) }
            }
            if let weather = model.weather {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let temperature = weather.temperature {
                            Text(String(format: "%.0f°", temperature))
                                .font(.system(size: min(76, min(size.width * 0.24, size.height * 0.30)), weight: .thin))
                            if let date = weather.observedAt, size.height >= 220 { Text(time(date, format: "HH:mm", zone: TimeZone(identifier: "Asia/Tokyo")!)+" 観測").font(.caption2).opacity(0.8) }
                        } else { Text("東京の予報").font(compact ? .title2 : .largeTitle) }
                    }
                    Spacer()
                    Image(systemName: weather.days.first?.symbol ?? "cloud.fill")
                        .symbolRenderingMode(.multicolor).font(.system(size: min(64, min(size.width * 0.22, size.height * 0.26))))
                        .accessibilityLabel(weather.days.first?.description ?? "天気")
                }
                if let today = weather.days.first {
                    Text(today.description).font(compact ? .caption : .body).lineLimit(compact ? 1 : 2)
                    if let high = today.high, let low = today.low, size.height >= 220 {
                        Text("最高:\(high)°  最低:\(low)°").font(.subheadline).opacity(0.85)
                    }
                }
                if model.showsHourly && size.height >= 280 { hourlyStrip(height: 150) }
                if !compact && size.height > 480 {
                    Divider().overlay(.white.opacity(0.25))
                    HStack {
                        ForEach(Array(weather.days.prefix(4).enumerated()), id: \.offset) { _, day in
                            VStack(spacing: 6) {
                                Text(time(day.date, format: "E", zone: TimeZone(identifier: "Asia/Tokyo")!)).font(.caption)
                                Image(systemName: day.symbol).symbolRenderingMode(.multicolor).font(.title3).accessibilityLabel(day.description)
                                Text(day.high.flatMap { high in day.low.map { "\(high)° / \($0)°" } } ?? "—").font(.caption2)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Link("気象庁", destination: JMAWeather.sourceURL)
                    Text(time(weather.issuedAt, format: "M/d HH:mm", zone: TimeZone(identifier: "Asia/Tokyo")!)+" 発表")
                    if model.error != nil || Date().timeIntervalSince(weather.fetchedAt) > 1200 || Date().timeIntervalSince(weather.issuedAt) > 86400 { Text("· 前回の情報") }
                }.font(.caption2).opacity(0.75)
            } else {
                Spacer(minLength: 0)
                if size.height >= 220 { Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: compact ? 32 : 54)) }
                Text(model.error ?? "東京の天気を取得しています").font(.callout)
                if model.error != nil { Button("再試行") { model.refresh(force: true) }.buttonStyle(.bordered) }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white).tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(weatherBackground.padding(-32))
        }
    }
    private func hourlyStrip(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: min(6, height * 0.025)) {
            Text("3時間ごとの予報").font(.caption).opacity(0.85)
            if model.hourly.isEmpty {
                Text(model.hourlyError ?? "予報を取得しています…").font(.caption).opacity(0.8)
            } else {
                GeometryReader { geometry in
                    let count = max(1, min(8, Int((geometry.size.width + 8) / 56)))
                    HStack(spacing: 8) {
                        ForEach(model.hourly.filter { $0.date >= model.now }.prefix(count)) { hour in
                            VStack(spacing: min(5, height * 0.02)) {
                                Text(time(hour.date, format: "H時", zone: TimeZone(identifier: "Asia/Tokyo")!)).font(.caption)
                                Image(systemName: hour.symbol).symbolRenderingMode(.multicolor).font(.system(size: min(20, height * 0.15)))
                                Text(String(format: "%.0f°", hour.temperature)).font(.system(size: 14, weight: .medium))
                                if height >= 130 { Text(hour.precipitationProbability.map { "雨 \($0)%" } ?? "—").font(.caption2).opacity(0.85) }
                            }
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        }
                    }.frame(width: geometry.size.width, alignment: .leading)
                }.frame(height: min(82, height * 0.58))
            }
            Link(model.hourlyError == nil ? "wttr.in / WorldWeatherOnline" : "wttr.in · 前回の予報", destination: ThreeHourlyWeather.sourceURL).font(.system(size: 9)).opacity(0.75)
        }
    }
    @Environment(\.colorScheme) private var colorScheme
    private var weatherBackground: LinearGradient {
        let colors = colorScheme == .dark
            ? [Color(red: 0.09, green: 0.22, blue: 0.39), Color(red: 0.12, green: 0.34, blue: 0.49)]
            : [Color(red: 0.18, green: 0.51, blue: 0.83), Color(red: 0.35, green: 0.67, blue: 0.91)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private func wideWeather(size: CGSize) -> some View {
        HStack(alignment: .top, spacing: min(20, size.width * 0.025)) {
            VStack(alignment: .leading, spacing: 5) {
                Text("東京").font(.system(size: min(18, size.height * 0.12), weight: .semibold))
                if let weather = model.weather {
                    Text(weather.temperature.map { String(format: "%.0f°", $0) } ?? "—")
                        .font(.system(size: min(48, size.height * 0.28), weight: .thin))
                    Text(weather.days.first?.description ?? "").font(.caption).lineLimit(size.height < 160 ? 1 : 2)
                    Spacer(minLength: 0)
                    Link(model.error == nil ? "気象庁" : "気象庁 · 前回の情報", destination: JMAWeather.sourceURL).font(.system(size: 9)).opacity(0.75)
                } else { Text(model.error ?? "取得しています…").font(.caption) }
            }.frame(width: min(180, size.width * 0.3), alignment: .leading)
            Divider().overlay(.white.opacity(0.3))
            hourlyStrip(height: size.height * 0.85).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white).tint(.white)
        .background(weatherBackground.padding(-32))
    }
}


private struct AnalogClockFace: View {
    let now: Date
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
            let seconds = Double(components.second ?? 0)
            let minutes = Double(components.minute ?? 0) + seconds / 60
            let hours = Double((components.hour ?? 0) % 12) + minutes / 60
            ZStack {
                Circle().fill(Color(nsColor: .textBackgroundColor)).shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                ForEach(0..<60) { tick in
                    Rectangle().fill(Color.primary.opacity(tick % 5 == 0 ? 0.85 : 0.3))
                        .frame(width: tick % 5 == 0 ? 2 : 1, height: side * (tick % 5 == 0 ? 0.045 : 0.022))
                        .offset(y: -radius * 0.9).rotationEffect(.degrees(Double(tick) * 6))
                }
                ForEach(1..<13) { hour in
                    Text(String(hour)).font(.system(size: side * 0.105, weight: .regular, design: .rounded))
                        .position(x: radius + sin(Double(hour) * .pi / 6) * radius * 0.71,
                                  y: radius - cos(Double(hour) * .pi / 6) * radius * 0.71)
                }
                hand(length: side * 0.25, width: side * 0.025, angle: hours * 30)
                hand(length: side * 0.36, width: side * 0.018, angle: minutes * 6)
                Capsule().fill(Color.orange).frame(width: max(1, side * 0.008), height: side * 0.46)
                    .offset(y: -side * 0.15).rotationEffect(.degrees(seconds * 6))
                Circle().fill(Color.orange).frame(width: side * 0.04, height: side * 0.04)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(now.formatted(date: .omitted, time: .standard))
    }
    private func hand(length: CGFloat, width: CGFloat, angle: Double) -> some View {
        Capsule().fill(Color.primary).frame(width: max(2, width), height: length)
            .offset(y: -length / 2 + width / 2).rotationEffect(.degrees(angle))
    }
}
