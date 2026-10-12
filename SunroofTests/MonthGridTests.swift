import Foundation
import Testing
@testable import Sunroof

@Suite struct MonthGridTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; c.locale = Locale(identifier: "en_US"); return c }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }

    @Test func mondayFirstOctober2026() {
        let days = MonthGrid.days(month: date(2026, 10, 15), firstWeekday: 2, calendar: cal, today: date(2026, 10, 12))
        #expect(days.count == 42)
        #expect(cal.component(.day, from: days[0].date) == 28) // Mon 28 Sep
        #expect(!days[0].inMonth)
        #expect(days[3].inMonth && cal.component(.day, from: days[3].date) == 1) // Thu 1 Oct
        #expect(days.filter(\.isToday).count == 1)
        #expect(cal.component(.day, from: days.first(where: \.isToday)!.date) == 12)
    }

    @Test func sundayFirstOctober2026() {
        let days = MonthGrid.days(month: date(2026, 10, 1), firstWeekday: 1, calendar: cal, today: date(2026, 1, 1))
        #expect(cal.component(.day, from: days[0].date) == 27) // Sun 27 Sep
        #expect(days.filter(\.isToday).isEmpty)
    }

    @Test func eventSpansEveryDayItTouches() {
        let keys = MonthGrid.dayKeys(start: date(2026, 10, 9, 22), end: date(2026, 10, 11, 9), calendar: cal)
        #expect(keys.map { cal.component(.day, from: $0) } == [9, 10, 11])
        // All-day events end at midnight of the next day: that day isn't included.
        let allDay = MonthGrid.dayKeys(start: date(2026, 10, 20, 0), end: date(2026, 10, 21, 0), calendar: cal)
        #expect(allDay.map { cal.component(.day, from: $0) } == [20])
    }

    @Test func weekdaySymbolsFollowFirstWeekday() {
        #expect(MonthGrid.weekdayInitials(firstWeekday: 2, calendar: cal).first == "M")
        #expect(MonthGrid.weekdayInitials(firstWeekday: 1, calendar: cal).first == "S")
    }

    // Review I8: after a day change, opening the shelf jumps back to today.
    @MainActor @Test func calendarReturnsToTodayOnNewDay() {
        let s = AppSettings(defaults: UserDefaults(suiteName: "c-\(UUID())")!)
        var now = date(2026, 9, 30)
        let m = CalendarModel(settings: s, now: { now })
        m.shiftMonth(-2)
        now = date(2026, 10, 1)
        m.start(); m.stop()
        #expect(cal.component(.month, from: m.month) == 10)
        #expect(m.selectedDay == Calendar.current.startOfDay(for: now))
    }
}
