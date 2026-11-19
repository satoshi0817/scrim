import Foundation

public struct WeatherHour: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let temperature: Double
    public let precipitationProbability: Int?
    public let code: Int
    public var id: Date { date }
    public var symbol: String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let hour = calendar.component(.hour, from: date), night = hour < 6 || hour >= 18
        switch code {
        case -1: return "questionmark.circle"
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.rain.fill"
        }
    }
    public init(date: Date, temperature: Double, precipitationProbability: Int?, code: Int) {
        self.date = date; self.temperature = temperature; self.precipitationProbability = precipitationProbability; self.code = code
    }
}
public enum ThreeHourlyWeather {
    public static let url = URL(string: "https://wttr.in/Tokyo?format=j1")!
    public static let sourceURL = URL(string: "https://wttr.in/Tokyo")!
    public static func parse(_ data: Data) throws -> [WeatherHour] {
        struct Response: Decodable { let weather: [Day] }
        struct Day: Decodable { let date: String; let hourly: [Hour] }
        struct Hour: Decodable { let time: String; let tempC: String; let weatherCode: String; let chanceofrain: String? }
        let days = try JSONDecoder().decode(Response.self, from: data).weather
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo"); formatter.dateFormat = "yyyy-MM-dd HH"
        return days.flatMap { day in
            day.hourly.compactMap { hour -> WeatherHour? in
                guard let clock = Int(hour.time), clock % 300 == 0, (0..<2400).contains(clock),
                      let temperature = Double(hour.tempC), temperature.isFinite, let code = Int(hour.weatherCode),
                      let date = formatter.date(from: day.date + " " + String(format: "%02d", clock / 100)) else { return nil }
                let probability = hour.chanceofrain.flatMap(Int.init).flatMap { (0...100).contains($0) ? $0 : nil }
                let wmo: Int
                switch code {
                case 113: wmo = 0
                case 116: wmo = 2
                case 119, 122: wmo = 3
                case 143, 248, 260: wmo = 45
                case 200, 386, 389, 392, 395: wmo = 95
                case 179, 182, 185, 227, 230, 323, 326, 329, 332, 335, 338, 350, 368, 371, 374, 377: wmo = 73
                case 176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308, 311, 314, 317, 320, 353, 356, 359, 362, 365: wmo = 61
                default: wmo = -1
                }
                return WeatherHour(date: date, temperature: temperature, precipitationProbability: probability, code: wmo)
            }
        }
    }
}
