import Foundation

struct WeatherCity: Codable, Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
}

struct Forecast: Codable, Equatable {
    struct Current: Codable, Equatable { var temperature: Double; var code: Int; var isDay: Bool }
    struct Hour: Codable, Equatable { var time: String; var temperature: Double; var code: Int }
    struct Day: Codable, Equatable { var date: String; var code: Int; var high: Double; var low: Double }
    var current: Current
    var hourly: [Hour] // next 6 hours from now
    var daily: [Day]   // today + 4
}

/// Open-Meteo (free, no API key): forecast + geocoding, and WMO weather-code mapping. Pure decoding/formatting.
enum OpenMeteo {
    static func forecastURL(_ c: WeatherCity) -> URL {
        var u = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        u.queryItems = [
            .init(name: "latitude", value: String(c.latitude)), .init(name: "longitude", value: String(c.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "6"),
        ]
        return u.url!
    }

    static func geocodingURL(_ query: String) -> URL {
        var u = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        u.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"), .init(name: "language", value: "en")]
        return u.url!
    }

    private struct Raw: Decodable {
        struct Current: Decodable {
            let time: String; let temperature_2m: Double; let weather_code: Int; let is_day: Int?
        }
        struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int] }
        struct Daily: Decodable {
            let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]
        }
        let current: Current; let hourly: Hourly; let daily: Daily
    }

    static func decode(_ data: Data) throws -> Forecast {
        let r = try JSONDecoder().decode(Raw.self, from: data)
        // Hourly times are local to the place: start at the current observation's hour.
        let start = r.hourly.time.firstIndex { $0 >= String(r.current.time.prefix(13)) } ?? 0
        let hours = r.hourly.time.indices.dropFirst(start).prefix(6).map {
            Forecast.Hour(time: r.hourly.time[$0], temperature: r.hourly.temperature_2m[$0], code: r.hourly.weather_code[$0])
        }
        let days = r.daily.time.indices.prefix(5).map {
            Forecast.Day(date: r.daily.time[$0], code: r.daily.weather_code[$0], high: r.daily.temperature_2m_max[$0],
                         low: r.daily.temperature_2m_min[$0])
        }
        return Forecast(current: .init(temperature: r.current.temperature_2m, code: r.current.weather_code,
                                       isDay: (r.current.is_day ?? 1) == 1),
                        hourly: Array(hours), daily: Array(days))
    }

    static func decodeCities(_ data: Data) throws -> [WeatherCity] {
        struct R: Decodable {
            struct C: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String?; let country: String? }
            let results: [C]?
        }
        return (try JSONDecoder().decode(R.self, from: data).results ?? []).map {
            WeatherCity(name: [$0.name, $0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                        latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    /// WMO weather interpretation codes → SF Symbol + short text.
    static func condition(code: Int, isDay: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0: (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1: (isDay ? "sun.max.fill" : "moon.fill", "Mostly Clear")
        case 2: (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly Cloudy")
        case 3: ("cloud.fill", "Cloudy")
        case 45, 48: ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57: ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67: ("cloud.rain.fill", "Rain")
        case 80, 81, 82: ("cloud.heavyrain.fill", "Showers")
        case 71, 73, 75, 77, 85, 86: ("cloud.snow.fill", "Snow")
        case 95, 96, 99: ("cloud.bolt.rain.fill", "Thunderstorm")
        default: ("questionmark", "—")
        }
    }

    static func format(_ celsius: Double, fahrenheit: Bool) -> String {
        let v = (fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded()
        return "\(Int(v == 0 ? 0 : v))°" // no "-0°"
    }
}
