import Foundation
import Testing
@testable import Sunroof

@Suite struct OpenMeteoTests {
    static let fixture = """
    {"current":{"time":"2026-10-12T10:00","temperature_2m":17.4,"weather_code":2,"is_day":1},
     "hourly":{"time":["2026-10-12T10:00","2026-10-12T11:00","2026-10-12T12:00","2026-10-12T13:00","2026-10-12T14:00","2026-10-12T15:00","2026-10-12T16:00","2026-10-12T17:00"],
               "temperature_2m":[17.4,18.1,19.0,19.6,19.2,18.4,17.0,15.9],"weather_code":[2,2,1,1,3,61,61,3]},
     "daily":{"time":["2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16","2026-10-17"],
              "weather_code":[2,61,3,0,71,95],"temperature_2m_max":[20.1,16.0,15.2,18.8,4.0,22.0],"temperature_2m_min":[11.2,9.8,8.1,7.5,-1.5,14.0]}}
    """

    @Test func decodesForecast() throws {
        let f = try OpenMeteo.decode(Data(Self.fixture.utf8))
        #expect(f.current.temperature == 17.4)
        #expect(f.current.code == 2)
        #expect(f.hourly.count == 6)
        #expect(f.daily.count == 5)
        #expect(f.daily[0].high == 20.1 && f.daily[0].low == 11.2)
    }

    @Test func conditions() {
        #expect(OpenMeteo.condition(code: 0, isDay: true).text == "Clear")
        #expect(OpenMeteo.condition(code: 0, isDay: false).symbol == "moon.stars.fill")
        #expect(OpenMeteo.condition(code: 2, isDay: true).text == "Partly Cloudy")
        #expect(OpenMeteo.condition(code: 61, isDay: true).text == "Rain")
        #expect(OpenMeteo.condition(code: 71, isDay: true).text == "Snow")
        #expect(OpenMeteo.condition(code: 95, isDay: true).text == "Thunderstorm")
        #expect(OpenMeteo.condition(code: 999, isDay: true).text == "—")
    }

    @Test func units() {
        #expect(OpenMeteo.format(20, fahrenheit: false) == "20°")
        #expect(OpenMeteo.format(20, fahrenheit: true) == "68°")
        #expect(OpenMeteo.format(-0.4, fahrenheit: false) == "0°")
    }

    // Review Focus 3: a failed refresh keeps showing the last forecast with its time.
    @MainActor @Test func cachedForecastSurvivesFailure() async throws {
        let d = UserDefaults(suiteName: "wx-\(UUID())")!
        let s = AppSettings(defaults: d)
        s.weatherCity = WeatherCity(name: "Lisbon", latitude: 38.72, longitude: -9.14)
        final class Flag: @unchecked Sendable { var fail = false }
        let flag = Flag()
        let model = WeatherModel(settings: s, defaults: d) { _ in
            if flag.fail { throw URLError(.notConnectedToInternet) }
            return Data(Self.fixture.utf8)
        }
        await model.refresh(force: true)
        #expect(model.forecast?.current.temperature == 17.4)
        flag.fail = true
        await model.refresh(force: true)
        #expect(model.forecast?.current.temperature == 17.4)
        #expect(model.lastError != nil)
        #expect(WeatherModel(settings: s, defaults: d) { _ in Data() }.forecast?.current.temperature == 17.4) // cached on disk
    }

    // Review I1: a cached forecast for another city is never shown for the current one.
    @MainActor @Test func cacheIsPerCity() async {
        let d = UserDefaults(suiteName: "wx-\(UUID())")!
        let s = AppSettings(defaults: d)
        s.weatherCity = WeatherCity(name: "London", latitude: 51.5, longitude: -0.1)
        let london = WeatherModel(settings: s, defaults: d) { _ in Data(Self.fixture.utf8) }
        await london.refresh(force: false)
        #expect(london.forecast != nil)
        s.weatherCity = WeatherCity(name: "Paris", latitude: 48.9, longitude: 2.35)
        let paris = WeatherModel(settings: s, defaults: d) { _ in throw URLError(.notConnectedToInternet) }
        #expect(paris.forecast == nil)
        await paris.refresh(force: false) // throttle must not apply to a different city
        #expect(paris.lastError != nil)
    }

    // Review I4: a new location fix only refetches when it actually moved.
    @Test func locationMoveThreshold() {
        let a = WeatherCity(name: "x", latitude: 38.72, longitude: -9.14)
        #expect(!WeatherModel.movedFar(from: a, to: WeatherCity(name: "x", latitude: 38.73, longitude: -9.15)))
        #expect(WeatherModel.movedFar(from: a, to: WeatherCity(name: "x", latitude: 41.15, longitude: -8.61)))
        #expect(WeatherModel.movedFar(from: nil, to: a))
    }
}
