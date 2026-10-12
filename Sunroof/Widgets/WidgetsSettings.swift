import EventKit
import SwiftUI

struct WidgetsSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var cityQuery = ""
    @State private var cityResults: [WeatherCity] = []
    @State private var calendars: [EKCalendar] = []
    @State private var reminderLists: [EKCalendar] = []
    private let store = EKEventStore()

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Widget area") {
                Toggle("Show widgets at the bottom of the shelf", isOn: $settings.showWidgets)
                Stepper("Rows: \(settings.widgetRows)", value: $settings.widgetRows, in: 1...4)
                Button("Reset Widget Layout") { settings.resetWidgetLayouts() }
            }
            Section("Calendar") {
                Picker("Week starts on", selection: $settings.calendarFirstWeekday) {
                    Text("System setting").tag(0)
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Saturday").tag(7)
                }
                ForEach(calendars, id: \.calendarIdentifier) { cal in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenCalendarIDs.contains(cal.calendarIdentifier) },
                        set: { on in
                            if on { settings.hiddenCalendarIDs.removeAll { $0 == cal.calendarIdentifier } }
                            else { settings.hiddenCalendarIDs.append(cal.calendarIdentifier) }
                        })) {
                        Label { Text(cal.title) } icon: { Circle().fill(Color(nsColor: cal.color)).frame(width: 9, height: 9) }
                    }
                }
                if calendars.isEmpty { Text("Allow calendar access from the Calendar widget to choose calendars.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Tasks") {
                Picker("Show tasks from", selection: $settings.taskListID) {
                    Text("Automatic (Reminders if allowed)").tag("")
                    Text("Sunroof (Tasks note)").tag(TasksModel.sunroofListID)
                    ForEach(reminderLists, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                }
            }
            Section("Weather") {
                LabeledContent("Location") {
                    Text(settings.weatherUseLocation ? "Current location" : settings.weatherCity?.name ?? "Not set").foregroundStyle(.secondary)
                }
                TextField("Search a city", text: $cityQuery)
                    .onChange(of: cityQuery) { _, q in Task { cityResults = await Self.searchCities(q) } }
                ForEach(cityResults.prefix(4), id: \.self) { c in
                    Button(c.name) { settings.weatherUseLocation = false; settings.weatherCity = c; cityQuery = ""; cityResults = [] }
                }
                Toggle("Use my location", isOn: $settings.weatherUseLocation)
                Picker("Units", selection: Binding(get: { settings.weatherFahrenheit.map { $0 ? 2 : 1 } ?? 0 },
                                                   set: { settings.weatherFahrenheit = $0 == 0 ? nil : $0 == 2 })) {
                    Text("Automatic").tag(0)
                    Text("°C").tag(1)
                    Text("°F").tag(2)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess { calendars = store.calendars(for: .event) }
            if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { reminderLists = store.calendars(for: .reminder) }
        }
    }

    private static func searchCities(_ q: String) async -> [WeatherCity] {
        guard q.trimmingCharacters(in: .whitespaces).count >= 2,
              let (data, _) = try? await URLSession.shared.data(from: OpenMeteo.geocodingURL(q)) else { return [] }
        return (try? OpenMeteo.decodeCities(data)) ?? []
    }
}
