import Foundation
import Testing
@testable import Sunroof

@MainActor @Suite struct WidgetLayoutTests {
    func at(_ p: [WidgetPlacement], _ k: WidgetKind) -> (Int, Int)? { p.first { $0.item.kind == k }.map { ($0.x, $0.y) } }

    @Test func defaultPacksOnOneRowOfTen() {
        let (placed, hidden) = WidgetLayout.default.pack(columns: 10, rows: 2)
        #expect(hidden.isEmpty)
        #expect(at(placed, .calendar)! == (0, 0))
        #expect(at(placed, .weather)! == (2, 0))
        #expect(at(placed, .music)! == (4, 0))
        #expect(at(placed, .tasks)! == (6, 0))
        #expect(at(placed, .stats)! == (8, 0))
    }

    @Test func firstFitFillsHoles() {
        let layout = WidgetLayout(items: [.init(kind: .calendar, size: .large), .init(kind: .stats, size: .small),
                                          .init(kind: .music, size: .small), .init(kind: .weather, size: .small)])
        let (placed, hidden) = layout.pack(columns: 3, rows: 2)
        #expect(at(placed, .stats)! == (2, 0))
        #expect(at(placed, .music)! == (2, 1))
        #expect(hidden.map(\.kind) == [.weather])
    }

    // Review Focus 1: shrinking hides the overflow (in order); growing brings it back.
    @Test func shrinkHidesAndGrowRestores() {
        let small = WidgetLayout.default.pack(columns: 4, rows: 2)
        #expect(small.placed.map(\.item.kind) == [.calendar, .weather, .music])
        #expect(small.hidden.map(\.kind) == [.tasks, .stats])
        #expect(WidgetLayout.default.pack(columns: 10, rows: 2).hidden.isEmpty)
    }

    @Test func moveResizeAddRemove() {
        var l = WidgetLayout.default
        l.move(.stats, toIndex: 0)
        #expect(l.items.first?.kind == .stats)
        l.resize(.stats, to: .medium)
        #expect(l.items.first?.size == .medium)
        l.resize(.stats, to: .large) // not allowed for stats
        #expect(l.items.first?.size == .medium)
        l.remove(.music)
        #expect(!l.items.map(\.kind).contains(.music))
        #expect(l.available == [.music])
        l.add(.music); l.add(.music)
        #expect(l.items.filter { $0.kind == .music }.count == 1)
        #expect(l.items.last?.size == WidgetKind.music.defaultSize)
    }

    @Test func settingsRoundTripPerDisplay() {
        let d = UserDefaults(suiteName: "w-\(UUID())")!
        let s = AppSettings(defaults: d)
        #expect(s.widgetLayout(forDisplay: "A") == .default)
        var l = WidgetLayout.default; l.remove(.music)
        s.setWidgetLayout(l, forDisplay: "A")
        #expect(AppSettings(defaults: d).widgetLayout(forDisplay: "A") == l)
        #expect(AppSettings(defaults: d).widgetLayout(forDisplay: "B") == .default)
        #expect(s.widgetRows == 2 && s.showWidgets)
    }

    // Review I6: nothing runs when the widget area is off; only placed widgets run.
    @Test func hostRespectsShowWidgetsAndPacking() {
        final class Spy: WidgetModel { var running = false; func start() { running = true }; func stop() { running = false } }
        let s = AppSettings(defaults: UserDefaults(suiteName: "h-\(UUID())")!)
        var spies: [WidgetKind: Spy] = [:]
        let host = WidgetHost(settings: s) { k in let x = Spy(); spies[k] = x; return x }
        s.showWidgets = false
        host.start(columns: 10)
        #expect(spies.values.allSatisfy { !$0.running })
        s.showWidgets = true
        host.start(columns: 4) // 4×2: calendar, weather, music fit; tasks and stats hidden
        #expect(spies[.calendar]?.running == true)
        #expect(spies[.stats]?.running != true)
    }
}
