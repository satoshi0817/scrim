import Foundation

public enum WidgetKind: String, CaseIterable, Codable { case weather, clock, calendar, upcoming, worldclock, calculator }
public enum ClockStyle: String, CaseIterable { case analog, digital }
public struct WidgetSpec: Equatable {
    public let kind: WidgetKind
    public let clockStyle: ClockStyle
    /// nil means all calendars; an empty set explicitly means none.
    public let calendarIDs: Set<String>?
    public let agendaDays: Int
    public let excludedKeywords: [String]
    public init(kind: WidgetKind, clockStyle: ClockStyle = .analog, calendarIDs: Set<String>? = nil, agendaDays: Int = 7, excludedKeywords: [String] = []) {
        self.kind = kind; self.clockStyle = kind == .clock ? clockStyle : .analog
        self.calendarIDs = kind == .upcoming ? calendarIDs : nil
        self.agendaDays = kind == .upcoming ? min(31, max(1, agendaDays)) : 7
        self.excludedKeywords = kind == .upcoming ? EventExclusion.normalized(excludedKeywords) : []
    }
    public init?(url: URL) {
        guard url.scheme == "scrim-widget", let host = url.host, let kind = WidgetKind(rawValue: host) else { return nil }
        self.kind = kind
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        clockStyle = kind == .clock ? items.first(where: { $0.name == "style" })?.value.flatMap(ClockStyle.init(rawValue:)) ?? .analog : .analog
        agendaDays = kind == .upcoming ? min(31, max(1, items.first(where: { $0.name == "days" })?.value.flatMap(Int.init) ?? 7)) : 7
        excludedKeywords = kind == .upcoming ? EventExclusion.normalized(items.filter { $0.name == "exclude" }.compactMap(\.value)) : []
        calendarIDs = kind == .upcoming && items.contains(where: { $0.name == "filter" && $0.value == "selected" })
            ? Set(items.filter { $0.name == "calendar" }.compactMap(\.value)) : nil
    }
    public var url: URL {
        var components = URLComponents(); components.scheme = "scrim-widget"; components.host = kind.rawValue
        var items: [URLQueryItem] = []
        if kind == .clock && clockStyle == .digital { items.append(URLQueryItem(name: "style", value: "digital")) }
        if kind == .upcoming, let calendarIDs {
            items.append(URLQueryItem(name: "filter", value: "selected"))
            items += calendarIDs.sorted().map { URLQueryItem(name: "calendar", value: $0) }
        }
        if kind == .upcoming && agendaDays != 7 { items.append(URLQueryItem(name: "days", value: String(agendaDays))) }
        if kind == .upcoming { items += excludedKeywords.map { URLQueryItem(name: "exclude", value: $0) } }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }
    public var title: String {
        switch kind { case .calculator: return "電卓"; case .worldclock: return "世界時計・勤務時間"; case .weather: return "東京の天気"; case .clock: return "時計"; case .calendar: return "月間カレンダー"; case .upcoming: return "次の予定" }
    }
}

public struct WeatherDay: Codable, Equatable, Sendable {
    public var date: Date
    public var code: Int
    public var description: String
    public var high: Int?
    public var low: Int?
    public var symbol: String {
        // JMA: hundreds identify the primary weather; compound codes describe
        // changes within the forecast period rather than a live observation.
        switch code {
        case 100: return "sun.max.fill"
        case 101, 110, 111: return "cloud.sun.fill"
        case 102: return "cloud.sun.rain.fill"
        case 200, 201, 210, 211: return "cloud.fill"
        case 400...499: return "cloud.snow.fill"
        case 300...399, 202...209, 212...299, 103...109, 112...199: return "cloud.rain.fill"
        default: return "cloud.fill"
        }
    }
}
public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var city: String
    public var issuedAt: Date
    public var fetchedAt: Date
    public var temperature: Double?
    public var observedAt: Date?
    public var days: [WeatherDay]
}

public enum JMAWeather {
    public static let forecastURL = URL(string: "https://www.jma.go.jp/bosai/forecast/data/forecast/130000.json")!
    public static let sourceURL = URL(string: "https://www.jma.go.jp/bosai/forecast/#area_type=offices&area_code=130000")!
    private struct Area: Decodable { var name: String; var code: String }
    private struct ForecastArea: Decodable {
        var area: Area
        var weatherCodes: [String]?
        var weathers: [String]?
        var temps: [String]?
        var tempsMin: [String]?
        var tempsMax: [String]?
    }
    private struct Series: Decodable { var timeDefines: [Date]; var areas: [ForecastArea] }
    private struct Report: Decodable { var reportDatetime: Date; var timeSeries: [Series] }
    public static func parseForecast(_ data: Data, fetchedAt: Date = Date()) throws -> WeatherSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reports = try decoder.decode([Report].self, from: data)
        guard let primary = reports.first else { throw CocoaError(.coderReadCorrupt) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var values: [Date: WeatherDay] = [:]
        for report in reports {
            for series in report.timeSeries {
                if let area = series.areas.first(where: { $0.area.code == "130010" }), let codes = area.weatherCodes {
                    for (index, date) in series.timeDefines.enumerated() where index < codes.count {
                        guard let code = Int(codes[index]) else { continue }
                        let key = calendar.startOfDay(for: date)
                        if values[key] == nil {
                            let description = area.weathers.flatMap { index < $0.count ? $0[index] : nil } ?? shortDescription(code)
                            values[key] = WeatherDay(date: key, code: code,
                                description: description.replacingOccurrences(of: "　", with: " "), high: nil, low: nil)
                        }
                    }
                }
                if let area = series.areas.first(where: { $0.area.code == "44132" }) {
                    if let temps = area.temps {
                        var highs: [Date: Int] = [:], lows: [Date: Int] = [:]
                        for (index, date) in series.timeDefines.enumerated() where index < temps.count {
                            guard let value = Int(temps[index]) else { continue }
                            let day = calendar.startOfDay(for: date)
                            // JMA daily temperature slots: 09:00 is the daytime
                            // high and 00:00 is the morning low, not observations.
                            if calendar.component(.hour, from: date) == 9 { highs[day] = value }
                            if calendar.component(.hour, from: date) == 0 { lows[day] = value }
                        }
                        for day in Set(highs.keys).union(lows.keys) {
                            if let high = highs[day], let low = lows[day], high < low { continue }
                            values[day]?.high = highs[day]; values[day]?.low = lows[day]
                        }
                    }
                    if let highs = area.tempsMax, let lows = area.tempsMin {
                        for (index, date) in series.timeDefines.enumerated() where index < highs.count && index < lows.count {
                            let key = calendar.startOfDay(for: date)
                            if values[key]?.high == nil { values[key]?.high = Int(highs[index]) }
                            if values[key]?.low == nil { values[key]?.low = Int(lows[index]) }
                        }
                    }
                }
            }
        }
        let days = values.values.sorted { $0.date < $1.date }
        guard !days.isEmpty else { throw CocoaError(.coderReadCorrupt) }
        return WeatherSnapshot(city: "東京", issuedAt: primary.reportDatetime, fetchedAt: fetchedAt, temperature: nil, observedAt: nil, days: days)
    }
    private static func shortDescription(_ code: Int) -> String {
        switch code/100 { case 1: return "晴れ"; case 2: return "くもり"; case 3: return "雨"; case 4: return "雪"; default: return "予報" }
    }
    public static func observationURL(latestTime: String) -> URL? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: latestTime.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let hour = calendar.component(.hour, from: date)/3*3
        let day = DateFormatter(); day.timeZone = calendar.timeZone; day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyyMMdd"
        return URL(string: "https://www.jma.go.jp/bosai/amedas/data/point/44132/\(day.string(from: date))_\(String(format: "%02d", hour)).json")
    }
    public static func observation(_ data: Data) throws -> (Double, Date)? {
        struct Record: Decodable { var temp: [Double?]? }
        let values = try JSONDecoder().decode([String: Record].self, from: data)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo"); formatter.dateFormat = "yyyyMMddHHmmss"
        for key in values.keys.sorted().reversed() {
            if let temp = values[key]?.temp, temp.count >= 2, let temperature = temp[0], temp[1] == 0,
               let date = formatter.date(from: key) { return (temperature, date) }
        }
        return nil
    }
}
