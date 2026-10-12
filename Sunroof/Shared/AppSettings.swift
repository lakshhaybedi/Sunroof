import Foundation
import Observation

enum ModifierKey: String, CaseIterable, Codable { case command, option, control, shift }
enum Theme: String, CaseIterable { case auto, light, dark }
enum ShelfMaterial: String, CaseIterable { case glass, solid }
enum ClipboardView: String, CaseIterable { case lastView, history, favorites }

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
    var accent: ColorChoice { didSet { save(accent.rawValue, "accent") } }
    /// Colour wash over the shelf background; nil = none.
    var shelfTint: ColorChoice? { didSet { save(shelfTint?.rawValue ?? "", "shelfTint") } }
    var noteFont: NoteFont { didSet { save(noteFont.rawValue, "noteFont") } }
    var panelOrder: [PanelID] { didSet { save(panelOrder.map(\.rawValue), "panelOrder") } }
    var enabledPanels: Set<PanelID> { didSet { save(enabledPanels.map(\.rawValue), "enabledPanels") } }
    var clipboardPaused: Bool { didSet { save(clipboardPaused, "clipboardPaused") } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }

    // Clipboard
    var historyLimit: Int { didSet { save(historyLimit, "historyLimit") } }
    var clipboardOpensWith: ClipboardView { didSet { save(clipboardOpensWith.rawValue, "clipboardOpensWith") } }
    var lastClipboardView: ClipboardView { didSet { save(lastClipboardView.rawValue, "lastClipboardView") } }
    var sensitiveApps: [String: SensitiveMode] {
        didSet { save((try? JSONEncoder().encode(sensitiveApps)) ?? Data(), "sensitiveApps") }
    }
    var favoritesFolder: URL { didSet { save(favoritesFolder.path, "favoritesFolder") } }

    // Files
    var filesFolder: URL { didSet { save(filesFolder.path, "filesFolder") } }
    var arrangeBy: ArrangeBy { didSet { save(arrangeBy.rawValue, "arrangeBy") } }
    var foldersOnTop: Bool { didSet { save(foldersOnTop, "foldersOnTop") } }
    var filesAsList: Bool { didSet { save(filesAsList, "filesAsList") } }
    var itemSizeIndex: Int { didSet { save(itemSizeIndex, "itemSizeIndex") } }
    var cleanupDays: Int { didSet { save(cleanupDays, "cleanupDays") } }
    var catchScreenshots: Bool { didSet { save(catchScreenshots, "catchScreenshots") } }
    static let itemSizes: [CGFloat] = [48, 64, 96, 128]

    // Notes
    var notesFolder: URL { didSet { save(notesFolder.path, "notesFolder") } }
    var noteFontSize: Double { didSet { save(noteFontSize, "noteFontSize") } }
    var notesShowList: Bool { didSet { save(notesShowList, "notesShowList") } }
    var lastNote: String? { didSet { save(lastNote ?? "", "lastNote") } }
    var lastNoteSelection: Int { didSet { save(lastNoteSelection, "lastNoteSelection") } }
    // Widgets
    var showWidgets: Bool { didSet { save(showWidgets, "showWidgets") } }
    var widgetRows: Int { didSet { save(widgetRows, "widgetRows") } }
    private var widgetLayouts: [String: WidgetLayout] {
        didSet { save((try? JSONEncoder().encode(widgetLayouts)) ?? Data(), "widgetLayouts") }
    }
    /// 0 = follow the system; 1 = Sunday … 7 = Saturday.
    var calendarFirstWeekday: Int { didSet { save(calendarFirstWeekday, "calendarFirstWeekday") } }
    var hiddenCalendarIDs: [String] { didSet { save(hiddenCalendarIDs, "hiddenCalendarIDs") } }
    var calendarMediumShowsAgenda: Bool { didSet { save(calendarMediumShowsAgenda, "calendarMediumShowsAgenda") } }
    func widgetLayout(forDisplay key: String) -> WidgetLayout { widgetLayouts[key] ?? .default }
    func setWidgetLayout(_ layout: WidgetLayout, forDisplay key: String) { widgetLayouts[key] = layout }

    /// Open sticky notes: filename → NSStringFromRect(frame).
    var stickies: [String: String] { didSet { save((try? JSONEncoder().encode(stickies)) ?? Data(), "stickies") } }
    /// Column the user last worked in; gets keyboard focus when the shelf opens.
    var lastPanel: PanelID { didSet { if lastPanel != oldValue { save(lastPanel.rawValue, "lastPanel") } } }
    static let noteFontSizes: [Double] = [12, 13, 14, 16, 18]
    static var defaultFilesFolder: URL { documents.appendingPathComponent("Sunroof Files") }
    var isDefaultFilesFolder: Bool { filesFolder.standardizedFileURL.path == Self.defaultFilesFolder.standardizedFileURL.path }

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
        accent = ColorChoice(rawValue: v("accent", "")) ?? .system
        shelfTint = ColorChoice(rawValue: v("shelfTint", ""))
        noteFont = NoteFont(rawValue: v("noteFont", "")) ?? .system
        panelOrder = ids("panelOrder") ?? PanelID.allCases
        enabledPanels = ids("enabledPanels").map(Set.init) ?? Set(PanelID.allCases)
        clipboardPaused = v("clipboardPaused", false)
        hasCompletedOnboarding = v("hasCompletedOnboarding", false)
        historyLimit = v("historyLimit", 50)
        clipboardOpensWith = ClipboardView(rawValue: v("clipboardOpensWith", "")) ?? .lastView
        lastClipboardView = ClipboardView(rawValue: v("lastClipboardView", "")) ?? .history
        sensitiveApps = (defaults.data(forKey: "settings.sensitiveApps"))
            .flatMap { try? JSONDecoder().decode([String: SensitiveMode].self, from: $0) } ?? [:]
        favoritesFolder = (defaults.string(forKey: "settings.favoritesFolder")).map { URL(fileURLWithPath: $0) }
            ?? Self.documents.appendingPathComponent("Sunroof Favorites")
        filesFolder = (defaults.string(forKey: "settings.filesFolder")).map { URL(fileURLWithPath: $0) } ?? Self.defaultFilesFolder
        arrangeBy = ArrangeBy(rawValue: v("arrangeBy", "")) ?? .kind
        foldersOnTop = v("foldersOnTop", true)
        filesAsList = v("filesAsList", false)
        itemSizeIndex = v("itemSizeIndex", 1)
        cleanupDays = v("cleanupDays", 0)
        catchScreenshots = v("catchScreenshots", false)
        notesFolder = (defaults.string(forKey: "settings.notesFolder")).map { URL(fileURLWithPath: $0) }
            ?? Self.documents.appendingPathComponent("Sunroof Notes")
        noteFontSize = v("noteFontSize", 14.0)
        notesShowList = v("notesShowList", false)
        lastNote = (defaults.string(forKey: "settings.lastNote")).flatMap { $0.isEmpty ? nil : $0 }
        lastNoteSelection = v("lastNoteSelection", 0)
        lastPanel = PanelID(rawValue: v("lastPanel", "")) ?? .notes
        showWidgets = v("showWidgets", true)
        calendarFirstWeekday = v("calendarFirstWeekday", 0)
        hiddenCalendarIDs = defaults.stringArray(forKey: "settings.hiddenCalendarIDs") ?? []
        calendarMediumShowsAgenda = v("calendarMediumShowsAgenda", false)
        widgetRows = v("widgetRows", 2)
        widgetLayouts = (defaults.data(forKey: "settings.widgetLayouts"))
            .flatMap { try? JSONDecoder().decode([String: WidgetLayout].self, from: $0) } ?? [:]
        stickies = (defaults.data(forKey: "settings.stickies")).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

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

extension AppSettings {
    var edgeConfig: EdgeTriggerConfig {
        EdgeTriggerConfig(scroll: scrollTrigger,
                          hold: holdTrigger ? holdModifier : nil,
                          wait: waitTrigger ? waitDelay : nil)
    }
}
