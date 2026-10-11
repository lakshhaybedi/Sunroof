import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 12) {
            Text("Sensitive Data").font(.headline)
            Text("Data from these applications will appear concealed and not saved to disk:")
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(settings.sensitiveApps.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.sensitiveApps[bundleID] ?? .conceal },
                            set: { settings.sensitiveApps[bundleID] = $0 }
                        )) {
                            Text("Conceal").tag(SensitiveMode.conceal)
                            Text("Ignore").tag(SensitiveMode.ignore)
                        }
                        .labelsHidden().frame(width: 110)
                    }
                    .tag(bundleID)
                }
            }
            .frame(height: 160)
            HStack(spacing: 0) {
                Button { addApp() } label: { Image(systemName: "plus").frame(width: 20) }
                Button { if let s = selection { settings.sensitiveApps[s] = nil } } label: {
                    Image(systemName: "minus").frame(width: 20)
                }
                .disabled(selection == nil)
            }
            .buttonStyle(.bordered)

            Form {
                Picker("Clipboard history keeps:", selection: $settings.historyLimit) {
                    Text("10 items").tag(10)
                    Text("25 items").tag(25)
                    Text("50 items").tag(50)
                }
                Picker("Clipboard opens with:", selection: $settings.clipboardOpensWith) {
                    Text("Last view").tag(ClipboardView.lastView)
                    Text("History").tag(ClipboardView.history)
                    Text("Favorites").tag(ClipboardView.favorites)
                }
                FolderPicker(title: "Store favorites in", url: $settings.favoritesFolder)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { settings.sensitiveApps[id] = .conceal }
        }
    }
}

/// App icon + name for a bundle ID.
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18) }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}
