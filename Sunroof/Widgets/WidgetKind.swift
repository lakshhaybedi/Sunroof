import Foundation

enum WidgetSize: String, Codable, CaseIterable {
    case small, medium, large

    /// Grid cells (columns, rows).
    var span: (w: Int, h: Int) {
        switch self {
        case .small: (1, 1)
        case .medium: (2, 1)
        case .large: (2, 2)
        }
    }

    var title: String { rawValue.capitalized }
}

enum WidgetKind: String, Codable, CaseIterable {
    case calendar, tasks, music, weather, stats

    var name: String {
        switch self {
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .music: "Music"
        case .weather: "Weather"
        case .stats: "System Stats"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .music: "music.note"
        case .weather: "cloud.sun"
        case .stats: "gauge.with.dots.needle.33percent"
        }
    }

    var allowedSizes: [WidgetSize] {
        switch self {
        case .calendar, .tasks: [.medium, .large]
        case .music, .stats: [.small, .medium]
        case .weather: [.small, .medium, .large]
        }
    }

    var defaultSize: WidgetSize {
        switch self {
        case .calendar: .large
        case .tasks, .music, .weather: .medium
        case .stats: .small
        }
    }
}
