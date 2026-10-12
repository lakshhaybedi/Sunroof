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
            Page(title: "General", symbol: "switch.2", height: 560, view: AnyView(GeneralSettings(updater: updater))),
            Page(title: "Files", symbol: "folder", height: 150, view: AnyView(FilesSettings())),
            Page(title: "Notes", symbol: "note.text", height: 190, view: AnyView(NotesSettings())),
            Page(title: "Clipboard", symbol: "clipboard", height: 480, view: AnyView(ClipboardSettings().padding(20))),
            Page(title: "Panels", symbol: "rectangle.split.3x1", height: 260, view: AnyView(PanelsSettings().padding(20))),
            Page(title: "Widgets", symbol: "square.grid.2x2", height: 560, view: AnyView(WidgetsSettings())),
            Page(title: "Appearance", symbol: "paintpalette", height: 300, view: AnyView(AppearanceSettings())),
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

    func show(tab: String? = nil) {
        if window == nil {
            window = makeWindow()
            window?.center()
        }
        if let tab, let tabs = window?.contentViewController as? NSTabViewController,
           let i = tabs.tabViewItems.firstIndex(where: { $0.label == tab }) {
            tabs.selectedTabViewItemIndex = i
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct GeneralSettings: View {
    var updater: SPUUpdater?
    @Environment(AppSettings.self) private var settings
    @State private var autoUpdates = true
    @State private var autoInstall = true
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
            Section("Updates") {
                if let updater {
                    Toggle("Automatically check for updates", isOn: $autoUpdates)
                        .onAppear { autoUpdates = updater.automaticallyChecksForUpdates }
                        .onChange(of: autoUpdates) { _, on in updater.automaticallyChecksForUpdates = on }
                    Toggle("Automatically download and install updates", isOn: $autoInstall)
                        .disabled(!autoUpdates)
                        .onAppear { autoInstall = updater.automaticallyDownloadsUpdates }
                        .onChange(of: autoInstall) { _, on in updater.automaticallyDownloadsUpdates = on }
                }
                LabeledContent("Sunroof \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    Button("Check Now") {
                        guard let updater else { Toast.show("Updates aren't set up for this build."); return }
                        NSApp.activate()
                        updater.checkForUpdates()
                    }
                    .disabled(updater == nil)
                }
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
            Toggle("Reduce effects", isOn: Binding(get: { settings.material == .solid },
                                                   set: { settings.material = $0 ? .solid : .glass }))
            Text("A solid shelf and widget strip instead of Liquid Glass and blur. Lighter on the GPU.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Accent:") {
                Swatches(choices: ColorChoice.allCases, selection: Binding(get: { settings.accent }, set: { settings.accent = $0 ?? .system }))
            }
            LabeledContent("Shelf tint:") {
                Swatches(choices: [nil] + ColorChoice.allCases.filter { $0 != .system },
                         selection: $settings.shelfTint)
            }
            Picker("Note font:", selection: $settings.noteFont) {
                ForEach(NoteFont.allCases, id: \.self) { f in
                    Text(f.title).font(Font(f.font(ofSize: 13))).tag(f)
                }
            }
            Text("Select \"Auto\" to match the current macOS appearance. Accent colours links, checkboxes and buttons.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// A row of colour dots; nil = "none" (a slashed circle).
private struct Swatches: View {
    let choices: [ColorChoice?]
    @Binding var selection: ColorChoice?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(choices, id: \.self) { choice in
                Button { selection = choice } label: {
                    ZStack {
                        if let choice {
                            // "System" follows macOS's accent: a rainbow, so it isn't mistaken for one of the colours.
                            Circle().fill(choice == .system
                                ? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                                : AnyShapeStyle(choice.color))
                        } else {
                            Circle().strokeBorder(.secondary, lineWidth: 1)
                            Image(systemName: "line.diagonal").font(.caption2).foregroundStyle(.secondary)
                        }
                        if selection == choice { Circle().strokeBorder(.primary, lineWidth: 2).padding(-3) }
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(HitButtonStyle(minSize: 22))
                .help(choice?.title ?? "None")
            }
        }
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
