import XCTest
@testable import ScrimCore

final class WidgetTests: XCTestCase {
    func testWidgetDescriptorsUseExistingURLPersistence() {
        for kind in WidgetKind.allCases {
            let spec = WidgetSpec(kind: kind)
            XCTAssertEqual(WidgetSpec(url: spec.url), spec)
            XCTAssertEqual(PanelSource.classify(spec.url), .widget(spec))
        }
        XCTAssertNil(WidgetSpec(url: URL(string: "scrim-widget://unknown")!))
    }
    func testCalendarSelectionPreservesAllNoneAndOpaqueIdentifiers() {
        XCTAssertNil(WidgetSpec(url: WidgetSpec(kind: .upcoming).url)?.calendarIDs)
        XCTAssertEqual(WidgetSpec(url: WidgetSpec(kind: .upcoming, calendarIDs: []).url)?.calendarIDs, Set<String>())
        let ids: Set<String> = ["account/calendar?x=1&y=2", "日本語 # + %"]
        let spec = WidgetSpec(kind: .upcoming, calendarIDs: ids)
        XCTAssertEqual(WidgetSpec(url: spec.url), spec)
    }
    func testForecastDoesNotInventCurrentTemperature() throws {
        let data = Data("""
        [{"reportDatetime":"2026-11-17T11:00:00+09:00","timeSeries":[
          {"timeDefines":["2026-11-17T11:00:00+09:00"],"areas":[{"area":{"name":"東京地方","code":"130010"},"weatherCodes":["214"],"weathers":["くもり　後　雨"]}]},
          {"timeDefines":["2026-11-17T00:00:00+09:00","2026-11-17T09:00:00+09:00"],"areas":[{"area":{"name":"東京","code":"44132"},"temps":["13","15"]}]}
        ]}]
        """.utf8)
        let snapshot = try JMAWeather.parseForecast(data)
        XCTAssertEqual(snapshot.city, "東京")
        XCTAssertNil(snapshot.temperature)
        XCTAssertEqual(snapshot.days.first?.high, 15)
        XCTAssertEqual(snapshot.days.first?.low, 13)
        XCTAssertEqual(snapshot.days.first?.description, "くもり 後 雨")
        XCTAssertEqual(snapshot.days.first?.symbol, "cloud.rain.fill")
    }
    func testMissingOrInvalidDataDoesNotLookLikeGoodWeather() throws {
        XCTAssertThrowsError(try JMAWeather.parseForecast(Data("[]".utf8)))
        XCTAssertThrowsError(try JMAWeather.parseForecast(Data("not json".utf8)))
        let data = Data("{\"20261117110000\":{\"temp\":[11.5,0]},\"20261117111000\":{\"temp\":[99,1]}}".utf8)
        XCTAssertEqual(try JMAWeather.observation(data)?.0, 11.5)
        XCTAssertNil(try JMAWeather.observation(Data("{\"20261117111000\":{\"temp\":[null,0]}}".utf8)))
        XCTAssertEqual(JMAWeather.observationURL(latestTime: "2026-11-17T11:20:00+09:00")?.lastPathComponent, "20261117_09.json")
    }
}
