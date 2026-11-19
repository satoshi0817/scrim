import AppKit
import SwiftUI

struct WorkCity: Identifiable, Codable {
    var id: String
    var start = 9
    var end = 18
    static let names = ["Asia/Tokyo":"東京", "Europe/London":"ロンドン", "America/Los_Angeles":"サンフランシスコ", "America/New_York":"ニューヨーク", "Europe/Paris":"パリ", "Europe/Berlin":"ベルリン", "Asia/Seoul":"ソウル", "Asia/Singapore":"シンガポール", "Asia/Kolkata":"ベンガルール", "Australia/Sydney":"シドニー"]
    static let initial = ["Asia/Tokyo", "Europe/London", "America/Los_Angeles"].map { WorkCity(id: $0) }
    var name: String { Self.names[id] ?? id.components(separatedBy: "/").last!.replacingOccurrences(of: "_", with: " ") }
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: id) ?? .gmt
        return cal
    }
    func working(_ date: Date) -> Bool {
        let cal = calendar
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)
        if start > end && hour < end { return (3...7).contains(weekday) }
        return (2...6).contains(weekday) && hour >= start && (start > end || hour < end)
    }
    func label(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f.string(from: date)
    }
}

struct WorldClockView: View {
    let now: Date
    @Binding var configuring: Bool
    @AppStorage("worldClockWorkCities.v1") private var saved = Data()
    @State private var selection: Date?
    private var cities: [WorkCity] {
        guard let result = try? JSONDecoder().decode([WorkCity].self, from: saved), !result.isEmpty else { return WorkCity.initial }
        return result
    }
    private func store(_ values: [WorkCity]) {
        if let data = try? JSONEncoder().encode(values) { saved = data }
    }
    private var instant: Date { selection ?? now }
    private var day: DateInterval { Calendar.current.dateInterval(of: .day, for: instant)! }
    private var slots: [Date] {
        (0..<Int(day.duration / 900)).map { day.start.addingTimeInterval(Double($0) * 900) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(configuring ? "都市と勤務時間" : "世界時計", systemImage: "globe").font(.headline)
                Spacer()
                if configuring { Button("完了") { configuring = false }.padding(.trailing, 28) }
                else {
                    Button { copyTimes() } label: { Image(systemName: "doc.on.doc") }.help("各地の日時をコピー")
                }
            }
            if configuring { settings } else { clocks }
        }.buttonStyle(.borderless)
    }
    private var clocks: some View {
        let rows = cities
        let ticks = slots
        let common = ticks.map { date in rows.allSatisfy { $0.working(date) } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { city in
                    VStack(spacing: 3) {
                        HStack {
                            Image(systemName: (6..<18).contains(city.calendar.component(.hour, from: instant)) ? "sun.max" : "moon")
                            Text(city.name).lineLimit(1)
                            Spacer()
                            Text(city.label(instant, format: "M/d(E)")).font(.caption).foregroundStyle(.secondary)
                            Text(city.label(instant, format: "HH:mm")).monospacedDigit().fontWeight(.semibold)
                        }
                        strip(ticks.map(city.working))
                    }.accessibilityElement(children: .combine)
                }
                Divider()
                Text(overlapLabel(common, ticks)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("前日")
                    Text(instant.formatted(.dateTime.month().day()) + " · " + TimeZone.current.identifier.components(separatedBy: "/").last!).font(.caption)
                    Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("翌日")
                    Spacer()
                    Button("現在") { selection = nil }
                }
                Slider(value: Binding(get: { min(Double(ticks.count-1), floor(instant.timeIntervalSince(day.start)/900)) }, set: { selection = ticks[Int($0)] }), in: 0...Double(ticks.count-1), step: 1)
                    .accessibilityLabel("各地の時刻を比較")
            }
        }
    }
    private func strip(_ active: [Bool]) -> some View {
        Canvas { context, size in
            let w = size.width / CGFloat(active.count)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.secondary.opacity(0.15)))
            for index in active.indices where active[index] {
                context.fill(Path(CGRect(x: CGFloat(index)*w, y: 0, width: w+0.3, height: size.height)), with: .color(.teal))
            }
            let x = size.width * instant.timeIntervalSince(day.start) / day.duration
            context.fill(Path(CGRect(x: min(x,size.width-2), y: 0, width: 2, height: size.height)), with: .color(.primary))
        }.frame(height: 7).clipShape(Capsule())
    }
    private func overlapLabel(_ active: [Bool], _ ticks: [Date]) -> String {
        var ranges: [String] = []
        var index = 0
        let local = WorkCity(id: TimeZone.current.identifier)
        while index < active.count {
            guard active[index] else { index += 1; continue }
            let start = ticks[index]
            repeat { index += 1 } while index < active.count && active[index]
            ranges.append(local.label(start, format: "HH:mm") + "–" + local.label(index < ticks.count ? ticks[index] : day.end, format: "HH:mm"))
        }
        return ranges.isEmpty ? "この日は全都市の勤務時間に重なりがありません" : "全都市の勤務時間（Macの時刻） " + ranges.joined(separator: "、")
    }
    private func shiftDay(_ days: Int) { selection = Calendar.current.date(byAdding: .day, value: days, to: instant) }
    private func copyTimes() {
        let text = cities.map { $0.name + " " + $0.label(instant, format: "yyyy/M/d(E) HH:mm z") }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("平日の勤務時間（各都市の現地時刻）").font(.caption)
                ForEach(cities) { city in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(city.name).fontWeight(.medium)
                            Spacer()
                            Button { store(cities.filter { $0.id != city.id }) } label: { Image(systemName: "minus.circle") }.disabled(cities.count == 1)
                        }
                        HStack { hourPicker(city, start: true); Text("–"); hourPicker(city, start: false) }
                    }
                }
                Menu("都市を追加") {
                    ForEach(WorkCity.names.keys.sorted(), id: \.self) { id in
                        if !cities.contains(where: { $0.id == id }) { Button(WorkCity(id: id).name) { store(cities + [WorkCity(id: id)]) } }
                    }
                    Menu("その他のタイムゾーン") {
                        ForEach(TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !WorkCity.names.keys.contains($0) && !cities.map(\.id).contains($0) }, id: \.self) { id in
                            Button(id) { store(cities + [WorkCity(id: id)]) }
                        }
                    }
                }
            }
        }
    }
    private func hourPicker(_ city: WorkCity, start: Bool) -> some View {
        Picker(start ? "開始" : "終了", selection: Binding(get: { start ? city.start : city.end }, set: { hour in
            var values = cities
            guard let i = values.firstIndex(where: { $0.id == city.id }) else { return }
            if start { values[i].start = hour } else { values[i].end = hour }
            store(values)
        })) {
            ForEach(0..<24) { h in Text(String(format: "%02d:00", h)).tag(h).disabled(h == (start ? city.end : city.start)) }
        }.labelsHidden()
    }
}
