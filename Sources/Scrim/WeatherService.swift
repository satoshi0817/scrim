import Foundation
import ScrimCore

protocol WeatherProviding: Sendable {
    func cached() async -> WeatherSnapshot?
    func hourlyForecast(force: Bool) async throws -> [WeatherHour]
    func fetch(force: Bool) async throws -> WeatherSnapshot
}

extension WeatherProviding { func hourlyForecast(force: Bool) async throws -> [WeatherHour] { [] } }

actor WeatherService: WeatherProviding {
    static let shared = WeatherService()
    private var value: WeatherSnapshot?
    private var hourly: [WeatherHour] = []
    private var hourlyFetched: Date?
    private let cacheURL: URL
    private let session: URLSession
    init(cacheDirectory: URL? = nil, session: URLSession = .shared) {
        self.session = session
        let folder = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scrim/Weather", isDirectory: true)
        cacheURL = folder.appendingPathComponent("tokyo-jma.json")
        value = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    }
    func cached() -> WeatherSnapshot? { value }
    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
    func hourlyForecast(force: Bool = false) async throws -> [WeatherHour] {
        if !force, let hourlyFetched, Date().timeIntervalSince(hourlyFetched) < 1800 { return hourly }
        let parsed = try ThreeHourlyWeather.parse(await data(ThreeHourlyWeather.url))
        guard !parsed.isEmpty else { throw URLError(.cannotParseResponse) }
        hourly = parsed; hourlyFetched = Date(); return parsed
    }
    func fetch(force: Bool = false) async throws -> WeatherSnapshot {
        if !force, let value, Date().timeIntervalSince(value.fetchedAt) < 600 { return value }
        var snapshot = try JMAWeather.parseForecast(await data(JMAWeather.forecastURL))
        // Observation is optional: a failed observation never turns a forecast
        // into a made-up current temperature or prevents forecast display.
        if let latest = try? await data(URL(string: "https://www.jma.go.jp/bosai/amedas/data/latest_time.txt")!),
           let text = String(data: latest, encoding: .utf8), let url = JMAWeather.observationURL(latestTime: text),
           let observation = try? await data(url), let pair = try? JMAWeather.observation(observation) {
            snapshot.temperature = pair.0; snapshot.observedAt = pair.1
        }
        value = snapshot
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(snapshot) { try? encoded.write(to: cacheURL, options: .atomic) }
        return snapshot
    }
}
