import AppKit
import KeyboardShortcuts
import os
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings

    override init() {
        // Move ShelfScroll-era settings and folders before anything reads them (never in the unit-test host).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { LegacyMigration.run() }
        settings = AppSettings()
        super.init()
    }
    /// Sparkle; started only in the real app (not the unit-test host).
    private(set) var updater: SPUStandardUpdaterController?
    private(set) var shelf: ShelfController!
    private var edgeMonitor: EdgeTriggerMonitor!
    private var statusItem: StatusItemController!
    private(set) var settingsWindow: SettingsWindowController!
    private let onboarding = OnboardingWindowController()
    private let onboardingState = OnboardingState()
    private var clipStore: ClipStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var paster: Paster!
    private var drawer: DrawerModel!
    private var cleanup: CleanupScheduler!
    private var screenshots: ScreenshotWatcher!
    private var noteStore: NoteStore!
    private(set) var notes: NotesController!
    private var search: GlobalSearch!
    private var stickies: StickyManager!
    private(set) var widgets: WidgetHost!
    private let searchRoot = OSAllocatedUnfairLock(initialState: URL(fileURLWithPath: "/"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host; don't show windows or install monitors there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.mainMenu = Self.editMenu()
        // Without a public EdDSA key (local/unsigned builds) Sparkle would alert "updater failed to start" at every launch.
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        if !key.isEmpty {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        shelf = ShelfController(settings: settings)
        setUpClipboard()
        setUpFiles()
        setUpNotes()
        setUpSearch()
        setUpWidgets()
        edgeMonitor = EdgeTriggerMonitor(settings: settings) { [weak self] decision in
            self?.handle(decision)
        }
        edgeMonitor.isSuspended = { [weak self] in self?.shelf.isVisible ?? false }
        shelf.onVisibilityChange = { [weak self] visible in
            self?.edgeMonitor.reset()
            if visible { self?.onboardingState.shelfOpened = true }
        }
        edgeMonitor.start()

        settingsWindow = SettingsWindowController(settings: settings, updater: updater?.updater)
        statusItem = StatusItemController(settings: settings,
                                          onToggle: { [weak self] in self?.toggleShelf() },
                                          onOpenSettings: { [weak self] in self?.settingsWindow.show() },
                                          onCheckForUpdates: { [weak self] in
                                              guard let updater = self?.updater else {
                                                  Toast.show("Updates aren't set up for this build.")
                                                  return
                                              }
                                              NSApp.activate()
                                              updater.checkForUpdates(nil)
                                          })

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.toggleShelf()
        }

        if !settings.hasCompletedOnboarding {
            onboarding.show(pages: OnboardingView.shellPages(state: onboardingState, settings: settings)) { [weak self] in
                self?.settings.hasCompletedOnboarding = true
            }
        } else if settings.openOnLaunch, let screen = Self.screenUnderMouse() {
            shelf.show(on: screen, focus: nil)
        }
    }

    private func setUpClipboard() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sunroof")
        clipStore = ClipStore(historyDir: support, favoritesDir: settings.favoritesFolder, limit: settings.historyLimit)
        clipboardMonitor = ClipboardMonitor(settings: settings, store: clipStore)
        clipboardMonitor.start()
        paster = Paster(store: clipStore, shelf: shelf)
        let (store, settings, paster) = (clipStore!, settings, paster!)
        shelf.descriptors = PanelDescriptor.placeholders.map { d in
            guard d.id == .clipboard else { return d }
            return PanelDescriptor(id: .clipboard, title: "Clipboard") { [weak self] in
                AnyView(ClipboardPanel(store: store, settings: settings, paster: paster, notes: self?.noteStore))
            }
        }
        shelf.onHide.append { ThumbnailCache.shared.purge() }
    }

    private func setUpFiles() {
        drawer = DrawerModel(root: settings.filesFolder, isDefaultRoot: settings.isDefaultFilesFolder)
        syncDrawer()
        cleanup = CleanupScheduler(settings: settings, model: drawer)
        cleanup.start()
        screenshots = ScreenshotWatcher(settings: settings)
        screenshots.start()
        let (drawer, settings) = (drawer!, settings)
        shelf.onShow.append { drawer.reload() } // picks up a custom folder that came back online
        shelf.descriptors = shelf.descriptors.map { d in
            guard d.id == .files else { return d }
            return PanelDescriptor(id: .files, title: "Files") { AnyView(FilesPanel(model: drawer, settings: settings)) }
        }
    }

    private func setUpNotes() {
        noteStore = NoteStore(folder: settings.notesFolder)
        notes = NotesController(store: noteStore, settings: settings)
        syncNotesFolder()
        let notes = notes!
        shelf.onHide.append { notes.finish() }
        noteStore.onSaveError = { Toast.show($0) }
        shelf.onShow.append { [weak self] in
            // Keyboard goes to the column used last (Notes by default) unless the shelf was opened for a specific one.
            guard let self, self.shelf.requestedFocus == nil else { return }
            self.focusLastPanel()
        }
        shelf.descriptors = shelf.descriptors.map { d in
            guard d.id == .notes else { return d }
            return PanelDescriptor(id: .notes, title: "Notes") { [weak self] in
                AnyView(NotesPanel(controller: notes, onFloat: { self?.stickies.open($0) }))
            }
        }
        stickies = StickyManager(store: noteStore, settings: settings)
        stickies.restore()
    }

    private func setUpWidgets() {
        widgets = WidgetHost(settings: settings) { [weak self] kind in self?.makeWidgetModel(kind) }
        let host = widgets!
        let band = NSHostingView(rootView: WidgetBand(host: host) { [weak self] kind, size in
            self?.widgetView(kind, size) ?? AnyView(WidgetPlaceholder(kind: kind))
        })
        shelf.setWidgetBand(band)
        shelf.onShow.append { [weak self] in
            guard let self, let key = self.shelf.displayKey else { return }
            host.displayKey = key
            host.start()
        }
        shelf.onHide.append { host.stop() }
    }

    /// Each widget's live model (filled in per widget).
    private func makeWidgetModel(_ kind: WidgetKind) -> WidgetModel? {
        switch kind {
        case .stats: StatsModel()
        case .calendar: CalendarModel(settings: settings)
        case .tasks: TasksModel(settings: settings, notes: noteStore)
        case .weather: WeatherModel(settings: settings)
        case .music: MusicModel()
        }
    }

    private func widgetView(_ kind: WidgetKind, _ size: WidgetSize) -> AnyView {
        let model = widgets.model(kind)
        switch kind {
        case .stats: if let m = model as? StatsModel { return AnyView(StatsWidget(model: m, size: size)) }
        case .calendar: if let m = model as? CalendarModel { return AnyView(CalendarWidget(model: m, size: size).environment(settings)) }
        case .tasks: if let m = model as? TasksModel { return AnyView(TasksWidget(model: m, size: size)) }
        case .weather: if let m = model as? WeatherModel { return AnyView(WeatherWidget(model: m, size: size)) }
        case .music: if let m = model as? MusicModel { return AnyView(MusicWidget(model: m, size: size)) }
        }
        return AnyView(WidgetPlaceholder(kind: kind))
    }

    private func setUpSearch() {
        let (clips, notesStore, root) = (clipStore!, noteStore!, searchRoot)
        search = GlobalSearch(
            clips: { q in
                var seen = Set<String>()
                return ClipStore.filter(clips.favorites + clips.history, query: q).filter { seen.insert($0.contentHash).inserted }
            },
            notes: { q in notesStore.search(q) },
            files: { q in DrawerModel.search(q, in: root.withLock { $0 }) })
        let host = NSHostingView(rootView: GlobalSearchView(search: search, settings: settings) { [weak self] hit in self?.activate(hit) })
        host.isHidden = true
        shelf.setOverlay(host)
        shelf.onGlobalSearch = { [weak self] in self?.setSearchVisible(!(self?.search.isVisible ?? true)) }
        shelf.escapeHandlers.append { [weak self] in
            guard let self, self.search.isVisible else { return false }
            self.setSearchVisible(false)
            return true
        }
        shelf.onHide.append { [weak self] in self?.setSearchVisible(false) }
    }

    private func setSearchVisible(_ visible: Bool) {
        let wasVisible = search.isVisible
        search.isVisible = visible
        if !visible { search.query = "" }
        shelfOverlay?.isHidden = !visible
        if wasVisible, !visible, shelf.isVisible { focusLastPanel() }
    }

    private func focusLastPanel() {
        let panel = settings.lastPanel
        guard settings.enabledPanels.contains(panel) else { return }
        if panel == .notes { notes.focus() }
        else { NotificationCenter.default.post(name: .shelfFocusPanel, object: panel.rawValue) }
    }

    private var shelfOverlay: NSView? { shelf.overlayView }

    private func activate(_ hit: SearchHit) {
        setSearchVisible(false)
        switch hit {
        case let .clip(c): paster.paste(c)
        case let .file(u): NSWorkspace.shared.open(u)
        case let .note(f, _, _):
            notes.open(f)
            DispatchQueue.main.async { self.notes.focus() }
        }
    }

    private func syncNotesFolder() {
        withObservationTracking {
            let folder = settings.notesFolder
            if noteStore.folder.path != folder.path {
                notes.finish()
                noteStore.folder = folder
                notes.restore()
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.syncNotesFolder() }
        }
    }

    /// Keep the drawer model in step with Files settings.
    private func syncDrawer() {
        withObservationTracking {
            let root = settings.filesFolder
            if drawer.root.path != canonical(root).path {
                drawer.changeRoot(root, isDefault: settings.isDefaultFilesFolder)
            } else if drawer.rootMissing {
                drawer.reload() // re-choosing the same folder after it reappears
            }
            searchRoot.withLock { $0 = root }
            drawer.arrangeBy = settings.arrangeBy
            drawer.foldersOnTop = settings.foldersOnTop
        } onChange: { [weak self] in
            Task { @MainActor in self?.syncDrawer() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipStore?.saveSync()
        notes?.finish()
        noteStore?.saveAll()
    }

    func toggleShelf() {
        guard let screen = Self.screenUnderMouse() else { return }
        shelf.toggle(on: screen)
    }

    private func handle(_ decision: EdgeDecision) {
        switch decision {
        case .none: break
        case let .open(i): if NSScreen.screens.indices.contains(i) { shelf.show(on: NSScreen.screens[i], focus: nil) }
        case let .openFiles(i): if NSScreen.screens.indices.contains(i) { shelf.show(on: NSScreen.screens[i], focus: .files) }
        }
    }

    /// Agent apps have no visible menu bar, but key equivalents (⌘C/⌘V/⌘X/⌘A/⌘Z) still route
    /// through the main menu — without it, text fields can't copy or paste.
    private static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        let item = NSMenuItem()
        item.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem()) // app menu slot
        main.addItem(item)
        return main
    }

    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }
}
