import AppKit
import SwiftUI
import Testing
@testable import Sunroof

@MainActor
@Suite struct SettingsWindowTests {
    // Regression: the settings window opened empty (zero-height content).
    @Test func settingsWindowHasRoomForContent() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let controller = SettingsWindowController(settings: settings, updater: nil)
        let window = controller.makeWindow()
        window.layoutIfNeeded()
        #expect(window.contentView!.frame.height >= 300)
        #expect(window.contentView!.frame.width >= 500)
    }

    @Test func everyTabIsPresent() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let tabs = SettingsWindowController(settings: settings, updater: nil).tabTitles
        #expect(tabs == ["General", "Files", "Notes", "Clipboard", "Panels", "Widgets", "Appearance", "Advanced"])
    }
}
