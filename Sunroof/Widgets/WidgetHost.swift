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

    init(settings: AppSettings, makeModel: @escaping (WidgetKind) -> WidgetModel? = { _ in nil }) {
        self.settings = settings
        self.makeModel = makeModel
    }

    var layout: WidgetLayout {
        get { settings.widgetLayout(forDisplay: displayKey) }
        set { settings.setWidgetLayout(newValue, forDisplay: displayKey); if running { start() } }
    }

    func model(_ kind: WidgetKind) -> WidgetModel? {
        if let m = models[kind] { return m }
        let m = makeModel(kind)
        models[kind] = m
        return m
    }

    /// Starts the models of widgets in the current layout; stops the rest.
    func start() {
        running = true
        let inLayout = Set(layout.items.map(\.kind))
        for kind in WidgetKind.allCases {
            if inLayout.contains(kind) { model(kind)?.start() } else { models[kind]?.stop() }
        }
    }

    func stop() {
        running = false
        models.values.forEach { $0.stop() }
    }
}
