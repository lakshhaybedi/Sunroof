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

    @Test func clipboardDefaults() {
        let s = AppSettings(defaults: defaults)
        #expect(s.historyLimit == 50)
        #expect(s.clipboardOpensWith == .lastView)
        #expect(s.lastClipboardView == .history)
        #expect(s.sensitiveApps.isEmpty)
        #expect(s.favoritesFolder.lastPathComponent == "ShelfScroll Favorites")
    }

    @Test func sensitiveAppsPersist() {
        AppSettings(defaults: defaults).sensitiveApps = ["com.1password.1password": .conceal]
        #expect(AppSettings(defaults: defaults).sensitiveApps == ["com.1password.1password": .conceal])
    }

    @Test func favoritesFolderPersists() {
        AppSettings(defaults: defaults).favoritesFolder = URL(fileURLWithPath: "/tmp/Favs")
        #expect(AppSettings(defaults: defaults).favoritesFolder.path == "/tmp/Favs")
    }

    @Test func filesDefaults() {
        let s = AppSettings(defaults: defaults)
        #expect(s.filesFolder.lastPathComponent == "ShelfScroll Files")
        #expect(s.isDefaultFilesFolder)
        #expect(s.arrangeBy == .kind)
        #expect(s.foldersOnTop)
        #expect(!s.filesAsList)
        #expect(s.itemSizeIndex == 1)
        #expect(s.cleanupDays == 0)
        #expect(!s.catchScreenshots)
        s.filesFolder = URL(fileURLWithPath: "/tmp/x")
        #expect(!s.isDefaultFilesFolder)
        #expect(AppSettings(defaults: defaults).filesFolder.path == "/tmp/x")
    }

    @Test func notesDefaults() {
        let s = AppSettings(defaults: defaults)
        #expect(s.notesFolder.lastPathComponent == "ShelfScroll Notes")
        #expect(s.noteFontSize == 14)
        #expect(!s.notesShowList)
        #expect(s.lastNote == nil)
        #expect(s.lastNoteSelection == 0)
        s.notesFolder = URL(fileURLWithPath: "/tmp/n")
        s.lastNote = "Ideas.md"
        let t = AppSettings(defaults: defaults)
        #expect(t.notesFolder.path == "/tmp/n")
        #expect(t.lastNote == "Ideas.md")
    }
}
