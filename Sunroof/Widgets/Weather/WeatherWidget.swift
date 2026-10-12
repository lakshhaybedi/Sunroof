import AppKit
import SwiftUI

struct WeatherWidget: View {
    let model: WeatherModel
    let size: WidgetSize

    var body: some View {
        Group {
            if model.locationDenied, model.settingsUseLocation {
                VStack(spacing: 6) {
                    AccessPrompt(symbol: "location.slash", text: "Location access is off", button: "Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                    }
                    Button("Choose a City Instead") { model.chooseCityInstead() }.buttonStyle(.link).font(.caption)
                }
            } else if model.city == nil {
                CityPicker(model: model)
            } else if let f = model.forecast {
                forecast(f)
            } else {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.lastError ?? "Loading…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom))
    }

    /// Sky colours for the current conditions (WMO codes): blue days, deep nights, grey cloud, dark storms.
    private var sky: [Color] {
        guard let c = model.forecast?.current else { return [Color.blue.opacity(0.3), Color.blue.opacity(0.06)] }
        let (top, bottom): (Color, Color) = switch c.code {
        case 0, 1: c.isDay ? (.blue, .cyan) : (.indigo, .black)
        case 2, 3, 45, 48: c.isDay ? (.gray, .blue) : (.gray, .indigo)
        case 95...: (.purple, .indigo)
        case 71...77, 85, 86: (.white, .cyan)
        default: c.isDay ? (.teal, .gray) : (.indigo, .gray) // drizzle and rain
        }
        return [top.opacity(0.45), bottom.opacity(0.12)]
    }

    private func t(_ c: Double) -> String { OpenMeteo.format(c, fahrenheit: model.fahrenheit) }

    @ViewBuilder private func forecast(_ f: Forecast) -> some View {
        let now = OpenMeteo.condition(code: f.current.code, isDay: f.current.isDay)
        VStack(alignment: .leading, spacing: size == .medium ? 4 : 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.placeName).font(.caption.bold()).lineLimit(1)
                    Text(t(f.current.temperature)).font(.system(size: size == .medium ? 30 : 36, weight: .light))
                }
                Spacer(minLength: 0)
                Image(systemName: now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
            }
            if size == .medium, let today = f.daily.first { // one line so the hours fit
                Text("\(now.text) · H:\(t(today.high)) L:\(t(today.low))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(now.text).font(.caption)
                    if let today = f.daily.first {
                        Text("H:\(t(today.high))  L:\(t(today.low))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if size != .small {
                HStack(spacing: 0) {
                    ForEach(Array(f.hourly.enumerated()), id: \.offset) { i, h in
                        VStack(spacing: 4) {
                            Text(i == 0 ? "Now" : String(h.time.suffix(5).prefix(2))).font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: OpenMeteo.condition(code: h.code, isDay: true).symbol)
                                .symbolRenderingMode(.multicolor).font(.caption)
                            Text(t(h.temperature)).font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if size == .large {
                Divider()
                ForEach(Array(f.daily.enumerated()), id: \.offset) { i, d in
                    HStack {
                        Text(i == 0 ? "Today" : weekday(d.date)).font(.caption).frame(width: 46, alignment: .leading)
                        Image(systemName: OpenMeteo.condition(code: d.code, isDay: true).symbol)
                            .symbolRenderingMode(.multicolor).font(.caption).frame(width: 22)
                        Spacer()
                        Text(t(d.low)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(t(d.high)).font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                    }
                }
            }
            if model.lastError != nil, let updated = model.updated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func weekday(_ isoDate: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: isoDate).map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? ""
    }
}

/// Search a city (Open-Meteo geocoding) or use the Mac's location.
struct CityPicker: View {
    let model: WeatherModel
    @State private var query = ""
    @State private var results: [WeatherCity] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Weather", systemImage: "cloud.sun").font(.caption.bold())
            TextField("Search a city", text: $query)
                .textFieldStyle(.roundedBorder).font(.caption)
                .onChange(of: query) { _, q in Task { results = await model.search(q) } }
            ForEach(results.prefix(3), id: \.self) { c in
                Button { model.choose(c) } label: { Text(c.name).font(.caption).lineLimit(1) }.buttonStyle(.hit)
            }
            Button("Use My Location") { model.useMyLocation() }.controlSize(.small)
        }
    }
}
