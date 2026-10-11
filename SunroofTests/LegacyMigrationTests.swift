import Foundation
import Testing
@testable import Sunroof

@MainActor
@Suite struct LegacyMigrationTests {
    let home = tempDir()
    var documents: URL { home.appendingPathComponent("Documents") }
    var support: URL { home.appendingPathComponent("Support") }
    let defaults = UserDefaults(suiteName: "new-\(UUID())")!
    let legacy = UserDefaults(suiteName: "old-\(UUID())")!

    func mkdir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    func run() { LegacyMigration.run(defaults: defaults, legacy: legacy, documents: documents, appSupport: support) }

    @Test func movesDefaultFoldersAndHistory() throws {
        for name in ["ShelfScroll Files", "ShelfScroll Notes", "ShelfScroll Favorites"] { try mkdir(documents.appendingPathComponent(name)) }
        try mkdir(support.appendingPathComponent("ShelfScroll"))
        try Data("note".utf8).write(to: documents.appendingPathComponent("ShelfScroll Notes/A.md"))
        run()
        #expect(FileManager.default.fileExists(atPath: documents.appendingPathComponent("Sunroof Notes/A.md").path))
        #expect(FileManager.default.fileExists(atPath: documents.appendingPathComponent("Sunroof Files").path))
        #expect(FileManager.default.fileExists(atPath: documents.appendingPathComponent("Sunroof Favorites").path))
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Sunroof").path))
        #expect(!FileManager.default.fileExists(atPath: documents.appendingPathComponent("ShelfScroll Notes").path))
    }

    @Test func neverOverwritesExistingSunroofFolder() throws {
        try mkdir(documents.appendingPathComponent("ShelfScroll Notes"))
        try mkdir(documents.appendingPathComponent("Sunroof Notes"))
        run()
        #expect(FileManager.default.fileExists(atPath: documents.appendingPathComponent("ShelfScroll Notes").path))
    }

    @Test func copiesSettingsAndRewritesDefaultPaths() {
        legacy.set(true, forKey: "settings.hasCompletedOnboarding")
        legacy.set("files", forKey: "settings.lastPanel")
        legacy.set("/Users/me/Documents/Unclutter Files", forKey: "settings.filesFolder")
        legacy.set(documents.appendingPathComponent("ShelfScroll Notes").path, forKey: "settings.notesFolder")
        legacy.set("hotkey", forKey: "KeyboardShortcuts_togglePanel")
        legacy.set("x", forKey: "unrelated")
        run()
        #expect(defaults.bool(forKey: "settings.hasCompletedOnboarding"))
        #expect(defaults.string(forKey: "settings.lastPanel") == "files")
        #expect(defaults.string(forKey: "settings.filesFolder") == "/Users/me/Documents/Unclutter Files") // custom: untouched
        #expect(defaults.string(forKey: "settings.notesFolder") == documents.appendingPathComponent("Sunroof Notes").path)
        #expect(defaults.string(forKey: "KeyboardShortcuts_togglePanel") == "hotkey")
        #expect(defaults.object(forKey: "unrelated") == nil)
    }

    @Test func runsOnce() {
        legacy.set("files", forKey: "settings.lastPanel")
        run()
        defaults.set("notes", forKey: "settings.lastPanel")
        run()
        #expect(defaults.string(forKey: "settings.lastPanel") == "notes")
    }
}
