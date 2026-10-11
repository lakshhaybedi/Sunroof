import AppKit
import KeyboardShortcuts
import Sparkle
import ServiceManagement
import SwiftUI

/// Native toolbar-style preferences window (like Unclutter's): one tab per section, each with a real size.
/// (A SwiftUI TabView of grouped Forms in a hosted window collapses to almost zero height.)
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let updater: SPUUpdater?

    init(settings: AppSettings, updater: SPUUpdater?) {
        self.settings = settings
        self.updater = updater
    }

    private struct Page { let title: String; let symbol: String; let height: CGFloat; let view: AnyView }

    private var pages: [Page] {
        [
            Page(title: "General", symbol: "switch.2", height: 420, view: AnyView(GeneralSettings(updater: updater))),
            Page(title: "Files", symbol: "folder", height: 150, view: AnyView(FilesSettings())),
            Page(title: "Notes", symbol: "note.text", height: 190, view: AnyView(NotesSettings())),
            Page(title: "Clipboard", symbol: "clipboard", height: 480, view: AnyView(ClipboardSettings().padding(20))),
            Page(title: "Panels", symbol: "rectangle.split.3x1", height: 260, view: AnyView(PanelsSettings().padding(20))),
            Page(title: "Appearance", symbol: "paintpalette", height: 210, view: AnyView(AppearanceSettings())),
            Page(title: "Advanced", symbol: "gearshape", height: 230, view: AnyView(AdvancedSettings())),
        ]
    }

    var tabTitles: [String] { pages.map(\.title) }

    func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for page in pages {
            let vc = NSHostingController(rootView: page.view.environment(settings))
            vc.sizingOptions = []
            vc.preferredContentSize = NSSize(width: 580, height: page.height)
            vc.view.frame.size = vc.preferredContentSize
            vc.title = page.title
            let item = NSTabViewItem(viewController: vc)
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: tabs)
        w.title = "Sunroof Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 580, height: pages[0].height))
        return w
    }

    func show() {
        if window == nil {
            window = makeWindow()
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct GeneralSettings: View {
    var updater: SPUUpdater?
    @Environment(AppSettings.self) private var settings
    @State private var autoUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle("Launch Sunroof at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }

            Section("To open Sunroof move your mouse to the very top of screen and") {
                Toggle("scroll down", isOn: $settings.scrollTrigger)
                HStack {
                    Toggle("hold", isOn: $settings.holdTrigger)
                    Picker("", selection: $settings.holdModifier) {
                        Text("⌘ Command Key").tag(ModifierKey.command)
                        Text("⌥ Option Key").tag(ModifierKey.option)
                        Text("⌃ Control Key").tag(ModifierKey.control)
                        Text("⇧ Shift Key").tag(ModifierKey.shift)
                    }
                    .labelsHidden().frame(width: 180)
                }
                HStack {
                    Toggle("wait", isOn: $settings.waitTrigger)
                    Picker("", selection: $settings.waitDelay) {
                        Text("a quarter second").tag(0.25)
                        Text("half a second").tag(0.5)
                        Text("one second").tag(1.0)
                        Text("two seconds").tag(2.0)
                    }
                    .labelsHidden().frame(width: 180)
                }
                KeyboardShortcuts.Recorder("or just press", name: .togglePanel)
            }
            Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            if let updater {
                Toggle("Automatically check for updates", isOn: $autoUpdates)
                    .onAppear { autoUpdates = updater.automaticallyChecksForUpdates }
                    .onChange(of: autoUpdates) { _, on in updater.automaticallyChecksForUpdates = on }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PanelsSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            ForEach(visiblePanels(order: settings.panelOrder, enabled: Set(PanelID.allCases)), id: \.self) { id in
                Toggle(id.displayName, isOn: Binding(
                    get: { settings.enabledPanels.contains(id) },
                    set: { on in if on { settings.enabledPanels.insert(id) } else { settings.enabledPanels.remove(id) } }
                ))
                // At least one panel must stay enabled.
                .disabled(settings.enabledPanels == [id])
            }
            .onMove { from, to in
                var order = visiblePanels(order: settings.panelOrder, enabled: Set(PanelID.allCases))
                order.move(fromOffsets: from, toOffset: to)
                settings.panelOrder = order
            }
        }
        .frame(height: 160)
        Text("Drag to reorder.").font(.caption).foregroundStyle(.secondary)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Theme:", selection: $settings.theme) {
                Text("Auto").tag(Theme.auto)
                Text("Light").tag(Theme.light)
                Text("Dark").tag(Theme.dark)
            }
            Text("Select \"Auto\" to match the current macOS appearance.").font(.caption).foregroundStyle(.secondary)
            Picker("Material:", selection: $settings.material) {
                Text("Liquid Glass").tag(ShelfMaterial.glass)
                Text("Solid").tag(ShelfMaterial.solid)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle(isOn: Binding(get: { !settings.openOnLaunch }, set: { settings.openOnLaunch = !$0 })) {
                Text("Do not open Sunroof window on the app's launch")
                Text("Check this option to make Sunroof launch quietly without showing the window.")
            }
            Toggle(isOn: $settings.invertScroll) {
                Text("Invert scrolling direction when opening Sunroof")
                Text("Check this option to fix the inverted scrolling direction for 3rd-party mouse device.")
            }
        }
        .formStyle(.grouped)
    }
}

extension PanelID {
    var displayName: String {
        switch self {
        case .clipboard: "Clipboard"
        case .files: "Files"
        case .notes: "Notes"
        }
    }
}
