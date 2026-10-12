import Observation
import SwiftUI

/// A widget's live data. Started when the shelf opens, stopped when it closes (no work while hidden).
@MainActor protocol WidgetModel: AnyObject {
    func start()
    func stop()
}

/// Owns the widget models and builds their views.
@MainActor @Observable
final class WidgetHost {
    let settings: AppSettings
    /// The display the shelf is on (layouts are per display).
    var displayKey = "default"
    /// Opens Settings › Widgets.
    @ObservationIgnored var openSettings: () -> Void = {}
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
