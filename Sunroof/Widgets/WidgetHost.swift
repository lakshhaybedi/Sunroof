import EventKit
import Observation
import os
import SwiftUI

/// A widget's live data. Started when the shelf opens, stopped when it closes (no work while hidden).
@MainActor protocol WidgetModel: AnyObject {
    func start()
    func stop()
}

let permissionLog = Logger(subsystem: "com.lakshhaybedi.Sunroof", category: "permissions")

/// Closes the shelf and brings Sunroof forward, then runs `request` — macOS permission dialogs open below the
/// shelf, and may not appear at all for a menu-bar app in the background.
@MainActor func askMacOS(_ request: @escaping @MainActor () async -> Void) {
    NotificationCenter.default.post(name: .shelfDismiss, object: nil)
    Task {
        try? await Task.sleep(for: .milliseconds(350)) // let the shelf slide away first
        NSApp.activate()
        await request()
    }
}

/// Asks for Calendar or Reminders access: the system dialog if never asked, otherwise the Privacy pane to turn it on.
@MainActor func requestEventKitAccess(_ type: EKEntityType, store: EKEventStore, then done: @escaping @MainActor () -> Void) {
    let name = type == .event ? "Calendars" : "Reminders"
    let status = EKEventStore.authorizationStatus(for: type)
    permissionLog.notice("\(name, privacy: .public) access requested; status \(status.rawValue, privacy: .public)")
    guard status == .notDetermined else {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(name)")!)
        done()
        return
    }
    askMacOS {
        do {
            let granted = try await type == .event ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders()
            permissionLog.notice("\(name, privacy: .public) request returned \(granted, privacy: .public)")
        } catch {
            permissionLog.error("\(name, privacy: .public) request failed: \(error.localizedDescription, privacy: .public)")
        }
        store.reset() // a store made before access was granted sees nothing until reset
        done()
    }
}

/// Owns the widget models and builds their views.
@MainActor @Observable
final class WidgetHost {
    let settings: AppSettings
    /// The display the shelf is on (layouts are per display).
    var displayKey = "default"
    /// Opens Settings › Widgets.
    @ObservationIgnored var openSettings: () -> Void = {}
    /// Rows the placed widgets (and the ＋) actually fill; the shelf sizes the widget strip to this.
    @ObservationIgnored var onRowsInUse: (Int) -> Void = { _ in }
    @ObservationIgnored private var models: [WidgetKind: WidgetModel] = [:]
    @ObservationIgnored private let makeModel: (WidgetKind) -> WidgetModel?
    @ObservationIgnored private var running = false
    /// Columns the band shows (reported by the band); widgets that don't fit don't run.
    @ObservationIgnored private(set) var columns = 10

    init(settings: AppSettings, makeModel: @escaping (WidgetKind) -> WidgetModel? = { _ in nil }) {
        self.settings = settings
        self.makeModel = makeModel
    }

    var layout: WidgetLayout {
        get { settings.widgetLayout(forDisplay: displayKey) }
        set { settings.setWidgetLayout(newValue, forDisplay: displayKey); restartIfRunning() }
    }

    func model(_ kind: WidgetKind) -> WidgetModel? {
        if let m = models[kind] { return m }
        let m = makeModel(kind)
        models[kind] = m
        return m
    }

    /// Starts the models of the widgets on screen; stops the rest (all of them when the widget area is off).
    func start(columns: Int? = nil) {
        running = true
        if let columns { self.columns = columns }
        let shown = settings.showWidgets
            ? Set(layout.pack(columns: self.columns, rows: settings.widgetRows).placed.map(\.item.kind)) : []
        for kind in WidgetKind.allCases {
            if shown.contains(kind) { model(kind)?.start() } else { models[kind]?.stop() }
        }
    }

    /// Re-applies `start` after the band's size or the widget settings changed (no-op while the shelf is closed).
    func restartIfRunning(columns: Int? = nil) {
        if running { start(columns: columns) } else if let columns { self.columns = columns }
    }

    func stop() {
        running = false
        models.values.forEach { $0.stop() }
    }
}
