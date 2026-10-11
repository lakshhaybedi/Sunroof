import Foundation
import Observation

enum ModifierKey: String, CaseIterable, Codable { case command, option, control, shift }
enum Theme: String, CaseIterable { case auto, light, dark }
enum ShelfMaterial: String, CaseIterable { case glass, solid }

/// All user settings, persisted to UserDefaults under "settings.<name>".
@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var scrollTrigger: Bool { didSet { save(scrollTrigger, "scrollTrigger") } }
    var holdTrigger: Bool { didSet { save(holdTrigger, "holdTrigger") } }
    var holdModifier: ModifierKey { didSet { save(holdModifier.rawValue, "holdModifier") } }
    var waitTrigger: Bool { didSet { save(waitTrigger, "waitTrigger") } }
    var waitDelay: Double { didSet { save(waitDelay, "waitDelay") } }
    var invertScroll: Bool { didSet { save(invertScroll, "invertScroll") } }
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
    var openOnLaunch: Bool { didSet { save(openOnLaunch, "openOnLaunch") } }
    var theme: Theme { didSet { save(theme.rawValue, "theme") } }
    var material: ShelfMaterial { didSet { save(material.rawValue, "material") } }
    var panelOrder: [PanelID] { didSet { save(panelOrder.map(\.rawValue), "panelOrder") } }
    var enabledPanels: Set<PanelID> { didSet { save(enabledPanels.map(\.rawValue), "enabledPanels") } }
    var clipboardPaused: Bool { didSet { save(clipboardPaused, "clipboardPaused") } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func v<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: "settings." + key) as? T ?? fallback }
        func ids(_ key: String) -> [PanelID]? {
            (defaults.stringArray(forKey: "settings." + key))?.compactMap(PanelID.init(rawValue:))
        }
        scrollTrigger = v("scrollTrigger", true)
        holdTrigger = v("holdTrigger", false)
        holdModifier = ModifierKey(rawValue: v("holdModifier", "")) ?? .command
        waitTrigger = v("waitTrigger", false)
        waitDelay = v("waitDelay", 0.5)
        invertScroll = v("invertScroll", false)
        showMenuBarIcon = v("showMenuBarIcon", true)
        openOnLaunch = v("openOnLaunch", false)
        theme = Theme(rawValue: v("theme", "")) ?? .auto
        material = ShelfMaterial(rawValue: v("material", "")) ?? .glass
        panelOrder = ids("panelOrder") ?? PanelID.allCases
        enabledPanels = ids("enabledPanels").map(Set.init) ?? Set(PanelID.allCases)
        clipboardPaused = v("clipboardPaused", false)
        hasCompletedOnboarding = v("hasCompletedOnboarding", false)
    }

    func height(forDisplay key: String) -> CGFloat? {
        (defaults.object(forKey: "settings.height." + key) as? Double).map { CGFloat($0) }
    }

    func setHeight(_ h: CGFloat, forDisplay key: String) {
        defaults.set(Double(h), forKey: "settings.height." + key)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: "settings." + key)
    }
}
