import AppKit
import SwiftUI

struct OnboardingPage: Identifiable {
    let id: String
    let view: AnyView
}

/// Live state the onboarding pages react to.
@MainActor @Observable
final class OnboardingState {
    var shelfOpened = false
    var accessibilityTrusted = Permissions.isAccessibilityTrusted
}

struct OnboardingView: View {
    let pages: [OnboardingPage]
    let onFinish: () -> Void
    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            pages[index].view
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            Divider()
            HStack {
                if index > 0 { Button("Back") { index -= 1 } }
                Spacer()
                if index < pages.count - 1 {
                    Button("Continue") { index += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: onFinish).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Shell pages (plans 2–4 insert theirs before "accessibility")

    static func shellPages(state: OnboardingState, settings: AppSettings) -> [OnboardingPage] {
        [
            .init(id: "welcome", view: AnyView(WelcomePage())),
            .init(id: "gesture", view: AnyView(GesturePage(state: state))),
            .init(id: "folders", view: AnyView(FoldersPage().environment(settings))),
            .init(id: "accessibility", view: AnyView(AccessibilityPage(state: state))),
        ]
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Welcome to Sunroof").font(.largeTitle.bold())
            Text("Your clipboard, files and notes, one scroll away.").foregroundStyle(.secondary)
        }
    }
}

private struct GesturePage: View {
    let state: OnboardingState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down")
                .font(.system(size: 56, weight: .semibold))
                .symbolEffect(.bounce, options: .repeating)
            Text("Move your pointer to the very top of the screen and scroll down.")
                .font(.title3).multilineTextAlignment(.center)
            Text(state.shelfOpened ? "Nice!" : "Try it")
                .font(.headline)
                .foregroundStyle(state.shelfOpened ? .green : .secondary)
        }
    }
}

/// Where Files and Notes live.
private struct FoldersPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 16) {
            Image(systemName: "folder").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text("Where should things live?").font(.title2.bold())
            Form {
                FolderPicker(title: "Files", url: $settings.filesFolder)
                FolderPicker(title: "Notes", url: $settings.notesFolder)
            }
            .formStyle(.grouped)
            Text("Put these in iCloud Drive or Dropbox to sync between Macs. macOS will ask once for access to your Documents folder.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

private struct AccessibilityPage: View {
    let state: OnboardingState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.accessibilityTrusted ? "checkmark.seal.fill" : "hand.raised")
                .font(.system(size: 48))
                .foregroundStyle(state.accessibilityTrusted ? .green : .accentColor)
            Text("Paste straight into any app").font(.title2.bold())
            Text("Sunroof needs Accessibility access to paste for you. Everything else works without it.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if !state.accessibilityTrusted {
                Button("Open Settings…") { Permissions.requestAccessibility() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
    }
}

/// Plain window for first-run onboarding. Closing it (Done or the close button) counts as finished.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinish: (() -> Void)?

    func show(pages: [OnboardingPage], onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        let view = OnboardingView(pages: pages) { [weak self] in self?.window?.close() }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Welcome to Sunroof"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onFinish?()
        onFinish = nil
        window = nil
    }
}
