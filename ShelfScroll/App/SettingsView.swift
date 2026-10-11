import AppKit
import KeyboardShortcuts
import Sparkle
import ServiceManagement
import SwiftUI

/// Hosts SettingsView in a plain window (SwiftUI's Settings scene can't be opened reliably from an agent app).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let updater: SPUUpdater?

    init(settings: AppSettings, updater: SPUUpdater?) {
        self.settings = settings
        self.updater = updater
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(updater: updater).environment(settings)))
            w.title = "ShelfScroll Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var updater: SPUUpdater?

    var body: some View {
        // Plans 2–4 insert Files, Notes and Clipboard tabs after General.
        TabView {
            GeneralSettings(updater: updater).tabItem { Label("General", systemImage: "switch.2") }
            FilesSettings().tabItem { Label("Files", systemImage: "folder") }
            NotesSettings().tabItem { Label("Notes", systemImage: "note.text") }
            ClipboardSettings().tabItem { Label("Clipboard", systemImage: "clipboard") }
            PanelsSettings().tabItem { Label("Panels", systemImage: "rectangle.split.3x1") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .frame(width: 560)
        .padding(20)
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
            Toggle("Launch ShelfScroll at login", isOn: $launchAtLogin)
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

            Section("To open ShelfScroll move your mouse to the very top of screen and") {
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
                Text("Do not open ShelfScroll window on the app's launch")
                Text("Check this option to make ShelfScroll launch quietly without showing the window.")
            }
            Toggle(isOn: $settings.invertScroll) {
                Text("Invert scrolling direction when opening ShelfScroll")
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
