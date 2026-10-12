import AppKit
import EventKit
import Observation

/// Tasks from Apple Reminders (when allowed) or Sunroof's own Tasks.md.
@MainActor @Observable
final class TasksModel: WidgetModel {
    struct List: Identifiable, Equatable { let id: String; let title: String; let color: NSColor? }
    static let sunroofListID = "sunroof"

    private(set) var remindersAllowed = false
    private(set) var remindersAsked = false
    private(set) var lists: [List] = []
    private(set) var reminders: [TaskItem] = []

    @ObservationIgnored let sunroof: SunroofTasksSource
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: Any?

    init(settings: AppSettings, notes: NoteStore) {
        self.settings = settings
        self.sunroof = SunroofTasksSource(store: notes)
    }

    /// The list shown: the saved choice, else Reminders' default list when allowed, else Sunroof.
    var currentListID: String {
        let saved = settings.taskListID
        if saved == Self.sunroofListID { return saved }
        if remindersAllowed {
            if !saved.isEmpty, lists.contains(where: { $0.id == saved }) { return saved }
            return store.defaultCalendarForNewReminders()?.calendarIdentifier ?? Self.sunroofListID
        }
        return Self.sunroofListID
    }

    var currentListTitle: String {
        currentListID == Self.sunroofListID ? "Sunroof" : lists.first { $0.id == currentListID }?.title ?? "Reminders"
    }

    var tasks: [TaskItem] { currentListID == Self.sunroofListID ? sunroof.tasks : reminders }

    func select(_ id: String) { settings.taskListID = id; reload() }

    func start() {
        refreshAccess()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func requestRemindersAccess() {
        requestEventKitAccess(.reminder, store: store) { [self] granted in
            if granted { grantedHere = true }
            refreshAccess()
            reload()
        }
    }

    func toggle(_ task: TaskItem) {
        if currentListID == Self.sunroofListID { sunroof.toggle(task.id); return }
        guard let r = store.calendarItem(withIdentifier: task.id) as? EKReminder else { return }
        r.isCompleted.toggle()
        try? store.save(r, commit: true)
        reload()
    }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if currentListID == Self.sunroofListID { sunroof.add(t); return }
        guard let list = store.calendar(withIdentifier: currentListID) else { return }
        let r = EKReminder(eventStore: store)
        r.title = t
        r.calendar = list
        try? store.save(r, commit: true)
        reload()
    }

    /// Access granted in this run (the static status may lag behind until relaunch).
    @ObservationIgnored private var grantedHere = false

    private func refreshAccess() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        remindersAllowed = grantedHere || status == .fullAccess
        remindersAsked = grantedHere || status != .notDetermined
    }

    private func reload() {
        guard remindersAllowed else { lists = []; reminders = []; return }
        lists = store.calendars(for: .reminder).map { List(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }
        guard currentListID != Self.sunroofListID, let list = store.calendar(withIdentifier: currentListID) else { reminders = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        store.fetchReminders(matching: predicate) { [weak self] found in
            let items = (found ?? []).map { r in
                TaskItem(id: r.calendarItemIdentifier, title: r.title ?? "", done: r.isCompleted,
                         due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
            }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in self?.reminders = items }
        }
    }
}
