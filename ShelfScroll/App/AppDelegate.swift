import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host; don't show windows or install monitors there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.mainMenu = Self.editMenu()
        shelf = ShelfController(settings: settings)
        setUpClipboard()
        setUpFiles()
        setUpNotes()
        edgeMonitor = EdgeTriggerMonitor(settings: settings) { [weak self] decision in
            self?.handle(decision)
        }
        edgeMonitor.isSuspended = { [weak self] in self?.shelf.isVisible ?? false }
        shelf.onVisibilityChange = { [weak self] visible in
            self?.edgeMonitor.reset()
            if visible { self?.onboardingState.shelfOpened = true }
        }
        edgeMonitor.start()

        settingsWindow = SettingsWindowController(settings: settings)
        statusItem = StatusItemController(settings: settings,
                                          onToggle: { [weak self] in self?.toggleShelf() },
                                          onOpenSettings: { [weak self] in self?.settingsWindow.show() })

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
            .appendingPathComponent("ShelfScroll")
        clipStore = ClipStore(historyDir: support, favoritesDir: settings.favoritesFolder, limit: settings.historyLimit)
        clipboardMonitor = ClipboardMonitor(settings: settings, store: clipStore)
        clipboardMonitor.start()
        paster = Paster(store: clipStore, shelf: shelf)
        let (store, settings, paster) = (clipStore!, settings, paster!)
        shelf.descriptors = PanelDescriptor.placeholders.map { d in
            guard d.id == .clipboard else { return d }
            return PanelDescriptor(id: .clipboard, title: "Clipboard") {
                AnyView(ClipboardPanel(store: store, settings: settings, paster: paster))
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
        shelf.onShow.append { [weak self] in
            // Typing goes straight into the note unless the shelf was opened for another column.
            guard let self, self.shelf.requestedFocus == nil, self.settings.enabledPanels.contains(.notes) else { return }
            notes.focus()
        }
        shelf.descriptors = shelf.descriptors.map { d in
            guard d.id == .notes else { return d }
            return PanelDescriptor(id: .notes, title: "Notes") { AnyView(NotesPanel(controller: notes)) }
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
