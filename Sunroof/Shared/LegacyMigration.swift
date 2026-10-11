import Foundation

/// One-time move from the app's earlier name (ShelfScroll): settings, hotkey, default folders and clipboard history.
/// Never overwrites anything that already exists under the new name; custom folders are left where they are.
enum LegacyMigration {
    static let legacyName = "ShelfScroll"
    static let legacyDomain = "com.lakshhaybedi.ShelfScroll"
    private static let doneKey = "settings.migratedFromShelfScroll"

    @MainActor static func run(defaults: UserDefaults = .standard,
                               legacy: UserDefaults? = UserDefaults(suiteName: legacyDomain),
                               documents: URL = AppSettings.documents,
                               appSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        let fm = FileManager.default

        var moves: [(URL, URL)] = ["Files", "Notes", "Favorites"].map {
            (documents.appendingPathComponent("\(legacyName) \($0)"), documents.appendingPathComponent("Sunroof \($0)"))
        }
        moves.append((appSupport.appendingPathComponent(legacyName), appSupport.appendingPathComponent("Sunroof")))
        for (old, new) in moves where fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }

        guard let legacy, defaults.object(forKey: "settings.hasCompletedOnboarding") == nil else { return }
        for (key, value) in legacy.dictionaryRepresentation()
        where key.hasPrefix("settings.") || key.hasPrefix("KeyboardShortcuts_") {
            if let path = value as? String, let moved = moves.first(where: { $0.0.path == path }) {
                defaults.set(moved.1.path, forKey: key) // default folder → its new name
            } else {
                defaults.set(value, forKey: key)
            }
        }
    }
}
