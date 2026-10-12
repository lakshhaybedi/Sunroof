import Foundation
import Testing
@testable import Sunroof

/// Every long-lived object must be freed once nothing uses it: timers, observers and folder watchers
/// hold their owners weakly, so a start/stop cycle can't leave a retain cycle behind.
@MainActor @Suite struct LeakTests {
    func freed(_ make: () -> AnyObject) async -> Bool {
        weak var ref: AnyObject?
        do { let o = make(); ref = o }
        try? await Task.sleep(for: .milliseconds(300)) // let any in-flight Task finish
        return ref == nil
    }

    @Test func widgetModelsAreFreedAfterStartStop() async {
        let s = AppSettings(defaults: UserDefaults(suiteName: "leak-\(UUID())")!)
        let notes = NoteStore(folder: tempDir())
        #expect(await freed { let m = StatsModel(); m.start(); m.stop(); return m })
        #expect(await freed { let m = CalendarModel(settings: s); m.start(); m.stop(); return m })
        #expect(await freed { let m = MusicModel(); m.start(); m.stop(); return m })
        #expect(await freed { let m = TasksModel(settings: s, notes: notes); m.start(); m.stop(); return m })
        #expect(await freed { let m = WeatherModel(settings: s, defaults: UserDefaults(suiteName: "lw-\(UUID())")!) { _ in throw URLError(.notConnectedToInternet) }
            m.start(); m.stop(); return m })
        #expect(await freed { let h = WidgetHost(settings: s) { _ in StatsModel() }; h.start(columns: 10); h.stop(); return h })
    }

    @Test func storesAndWatchersAreFreed() async {
        #expect(await freed { NoteStore(folder: tempDir()) })
        #expect(await freed { FolderWatcher(url: tempDir()) {} })
        #expect(await freed { DrawerModel(root: tempDir(), isDefaultRoot: false) })
        #expect(await freed { ClipStore(historyDir: tempDir(), favoritesDir: tempDir(), limit: 10) })
    }

    // The check itself must catch a real cycle.
    @Test func detectsACycle() async {
        final class Loop { var keep: (() -> Void)?; init() { keep = { _ = self } } }
        #expect(!(await freed { Loop() }))
    }
}
