import AppKit
import EventKit
import Observation

/// Calendar events for the visible month (EventKit). Listens for changes only while the shelf is open.
@MainActor @Observable
final class CalendarModel: WidgetModel {
    enum Access { case unknown, granted, denied }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let color: NSColor
    }

    private(set) var access: Access = .unknown
    var month: Date { didSet { reload() } }
    var selectedDay: Date
    private(set) var eventsByDay: [Date: [Event]] = [:]

    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private let now: () -> Date
    /// The day `goToToday` last ran; a new day sends the widget back to today on the next open.
    @ObservationIgnored private var today: Date

    init(settings: AppSettings, now: @escaping () -> Date = { .now }) {
        self.settings = settings
        self.now = now
        month = now()
        today = Calendar.current.startOfDay(for: now())
        selectedDay = today
    }

    var calendar: Calendar {
        var c = Calendar.current
        if settings.calendarFirstWeekday != 0 { c.firstWeekday = settings.calendarFirstWeekday }
        return c
    }

    var grid: [MonthGrid.Day] { MonthGrid.days(month: month, firstWeekday: calendar.firstWeekday, calendar: calendar) }
    var selectedEvents: [Event] { eventsByDay[selectedDay] ?? [] }

    /// The next `n` events from now.
    func upcoming(_ n: Int) -> [Event] {
        let now = now()
        return eventsByDay.values.flatMap { $0 }.filter { $0.end > now }
            .reduce(into: [String: Event]()) { $0[$1.id] = $1 }.values
            .sorted { $0.start < $1.start }.prefix(n).map { $0 }
    }

    func start() {
        if calendar.startOfDay(for: now()) != today { goToToday() }
        refreshAccess()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func requestAccess() {
        askMacOS { [self] in
            _ = try? await store.requestFullAccessToEvents()
            store.reset() // a store made before access was granted sees no calendars until reset
            refreshAccess()
            reload()
        }
    }

    func shiftMonth(_ delta: Int) { month = calendar.date(byAdding: .month, value: delta, to: month) ?? month }

    func goToToday() {
        today = calendar.startOfDay(for: now())
        selectedDay = today
        month = now()
    }

    private func refreshAccess() {
        access = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    private func reload() {
        guard access == .granted, let first = grid.first?.date, let last = grid.last?.date else { eventsByDay = [:]; return }
        let hidden = Set(settings.hiddenCalendarIDs)
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { eventsByDay = [:]; return }
        let end = calendar.date(byAdding: .day, value: 1, to: last)!
        let predicate = store.predicateForEvents(withStart: first, end: end, calendars: calendars)
        var byDay: [Date: [Event]] = [:]
        for e in store.events(matching: predicate) {
            let event = Event(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)", title: e.title ?? "Untitled",
                              start: e.startDate, end: e.endDate, allDay: e.isAllDay, color: e.calendar.color ?? .controlAccentColor)
            for key in MonthGrid.dayKeys(start: e.startDate, end: e.endDate, calendar: calendar) { byDay[key, default: []].append(event) }
        }
        for k in byDay.keys { byDay[k]?.sort { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) } }
        eventsByDay = byDay
    }

    #if DEBUG
    /// Renders and tests without Calendar permission.
    func usePreviewEvents(_ events: [Event]) {
        access = .granted
        var byDay: [Date: [Event]] = [:]
        for e in events { for k in MonthGrid.dayKeys(start: e.start, end: e.end, calendar: calendar) { byDay[k, default: []].append(e) } }
        eventsByDay = byDay
    }
    #endif

    /// Opens Calendar.app (events are edited there).
    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
