import CoreLocation
import Foundation
import Observation

/// Weather for the chosen city (or the Mac's location), refreshed at most every 30 min while the shelf is open.
@MainActor @Observable
final class WeatherModel: NSObject, WidgetModel, CLLocationManagerDelegate {
    private(set) var forecast: Forecast?
    private(set) var updated: Date?
    private(set) var lastError: String?
    private(set) var loading = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var location: CLLocationManager?
    @ObservationIgnored private var located: WeatherCity?
    static let interval: TimeInterval = 30 * 60
    private static let cacheKey = "widgets.weather.cache"

    private struct Cache: Codable { let forecast: Forecast; let updated: Date; let city: WeatherCity }

    init(settings: AppSettings, defaults: UserDefaults = .standard,
         fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }) {
        self.settings = settings
        self.defaults = defaults
        self.fetch = fetch
        super.init()
        if let data = defaults.data(forKey: Self.cacheKey), let c = try? JSONDecoder().decode(Cache.self, from: data) {
            forecast = c.forecast
            updated = c.updated
        }
    }

    var fahrenheit: Bool { settings.weatherFahrenheit ?? (Locale.current.measurementSystem == .us) }
    var city: WeatherCity? { settings.weatherUseLocation ? located : settings.weatherCity }
    var placeName: String { settings.weatherUseLocation ? (located?.name ?? "Current Location") : (settings.weatherCity?.name.components(separatedBy: ",").first ?? "") }

    func start() {
        if settings.weatherUseLocation { requestLocation() }
        Task { await refresh(force: false) }
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.refresh(force: false) } }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(force: Bool) async {
        guard let city else { return }
        if !force, let updated, Date.now.timeIntervalSince(updated) < Self.interval, forecast != nil { return }
        loading = true
        defer { loading = false }
        do {
            let f = try OpenMeteo.decode(try await fetch(OpenMeteo.forecastURL(city)))
            forecast = f
            updated = .now
            lastError = nil
            if let data = try? JSONEncoder().encode(Cache(forecast: f, updated: .now, city: city)) {
                defaults.set(data, forKey: Self.cacheKey)
            }
        } catch {
            lastError = "Couldn't update" // keep showing the last forecast
        }
    }

    func search(_ query: String) async -> [WeatherCity] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let data = try? await fetch(OpenMeteo.geocodingURL(q)) else { return [] }
        return (try? OpenMeteo.decodeCities(data)) ?? []
    }

    func choose(_ c: WeatherCity) {
        settings.weatherUseLocation = false
        settings.weatherCity = c
        forecast = nil
        Task { await refresh(force: true) }
    }

    // MARK: - Location ("Use my location")

    func useMyLocation() {
        settings.weatherUseLocation = true
        requestLocation()
    }

    private func requestLocation() {
        let m = location ?? CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        location = m
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
        m.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let c = l.coordinate
        Task { @MainActor in
            self.located = WeatherCity(name: "Current Location", latitude: c.latitude, longitude: c.longitude)
            await self.refresh(force: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.lastError = "Location unavailable" }
    }
}
