import Foundation

/// The 6 × 7 grid of days shown for a month (pure date math).
enum MonthGrid {
    struct Day: Identifiable, Equatable {
        var id: Date { date }
        let date: Date      // start of day
        let inMonth: Bool
        let isToday: Bool
    }

    /// 42 days starting on the `firstWeekday` (1 = Sunday … 7 = Saturday) on or before the 1st of `month`.
    static func days(month: Date, firstWeekday: Int, calendar: Calendar, today: Date = .now) -> [Day] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday - firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first)!
        let monthValue = calendar.component(.month, from: first)
        return (0..<42).map { i in
            let d = calendar.startOfDay(for: calendar.date(byAdding: .day, value: i, to: start)!)
            return Day(date: d, inMonth: calendar.component(.month, from: d) == monthValue,
                       isToday: calendar.isDate(d, inSameDayAs: today))
        }
    }

    /// Start-of-day keys for every day an event touches (an end exactly at midnight doesn't count that day).
    static func dayKeys(start: Date, end: Date, calendar: Calendar) -> [Date] {
        var keys: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = end > start ? end.addingTimeInterval(-1) : start
        while day <= last {
            keys.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            if keys.count > 62 { break } // very long events: the visible grid is at most 42 days anyway
        }
        return keys
    }

    static func weekdayInitials(firstWeekday: Int, calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols // Sunday first
        return (0..<7).map { symbols[(firstWeekday - 1 + $0) % 7] }
    }
}
