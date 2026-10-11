import Foundation
import Testing
@testable import ShelfScroll

@MainActor
@Suite struct AppSettingsTests {
    let defaults = UserDefaults(suiteName: "test-\(UUID())")!

    @Test func defaultsMatchUnclutter() {
        let s = AppSettings(defaults: defaults)
        #expect(s.scrollTrigger == true)
        #expect(s.holdTrigger == false)
        #expect(s.holdModifier == .command)
        #expect(s.waitTrigger == false)
        #expect(s.waitDelay == 0.5)
        #expect(s.invertScroll == false)
        #expect(s.showMenuBarIcon == true)
        #expect(s.openOnLaunch == false)
        #expect(s.theme == .auto)
        #expect(s.material == .glass)
        #expect(s.panelOrder == [.clipboard, .files, .notes])
        #expect(s.enabledPanels == Set(PanelID.allCases))
        #expect(s.hasCompletedOnboarding == false)
    }

    @Test func persistsAcrossInstances() {
        let a = AppSettings(defaults: defaults)
        a.waitTrigger = true
        a.waitDelay = 1
        a.panelOrder = [.notes, .files, .clipboard]
        a.enabledPanels = [.notes]
        let b = AppSettings(defaults: defaults)
        #expect(b.waitTrigger == true)
        #expect(b.waitDelay == 1)
        #expect(b.panelOrder == [.notes, .files, .clipboard])
        #expect(b.enabledPanels == [.notes])
    }

    @Test func heightPerDisplay() {
        let s = AppSettings(defaults: defaults)
        s.setHeight(420, forDisplay: "A")
        #expect(s.height(forDisplay: "A") == 420)
        #expect(s.height(forDisplay: "B") == nil)
    }
}
