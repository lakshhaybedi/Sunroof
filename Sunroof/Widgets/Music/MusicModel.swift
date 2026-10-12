import AppKit
import Observation

/// Now playing in Apple Music / Spotify. Event-driven (their distributed notifications) while the shelf is open;
/// AppleScript only talks to a player that is already running, so Sunroof never launches one.
@MainActor @Observable
final class MusicModel: WidgetModel {
    private(set) var music: NowPlaying?
    private(set) var spotify: NowPlaying?
    private(set) var lastStarted: NowPlaying.App?
    private(set) var permissionDenied = false

    @ObservationIgnored private var observers: [(NotificationCenter, Any)] = []

    var current: NowPlaying? { NowPlaying.merge(music: music, spotify: spotify, lastStarted: lastStarted) }

    func start() {
        guard observers.isEmpty else { return }
        let dist = DistributedNotificationCenter.default()
        for (name, app) in [("com.apple.Music.playerInfo", NowPlaying.App.music), ("com.spotify.client.PlaybackStateChanged", .spotify)] {
            let token = dist.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] n in
                let playing = (n.userInfo?["Player State"] as? String) == "Playing"
                MainActor.assumeIsolated {
                    if playing { self?.lastStarted = app }
                    self?.refresh(app)
                }
            }
            observers.append((dist, token))
        }
        let ws = NSWorkspace.shared.notificationCenter
        let token = ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if id == NowPlaying.App.music.bundleID { self?.music = nil }
                if id == NowPlaying.App.spotify.bundleID { self?.spotify = nil }
            }
        }
        observers.append((ws, token))
        refresh(.music)
        refresh(.spotify)
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    static func isRunning(_ app: NowPlaying.App) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    static func isInstalled(_ app: NowPlaying.App) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    #if DEBUG
    func usePreview(_ np: NowPlaying) { if np.app == .music { music = np } else { spotify = np } }
    #endif

    // MARK: - Controls

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func open(_ app: NowPlaying.App) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func command(_ verb: String) {
        guard let app = current?.app, Self.isRunning(app) else { return }
        _ = run("tell application \"\(app.scriptName)\" to \(verb)")
        refresh(app)
    }

    // MARK: - Reading state

    private func refresh(_ app: NowPlaying.App) {
        guard Self.isRunning(app) else { set(app, nil); return }
        let script = """
        tell application "\(app.scriptName)"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (player state as string) & linefeed & (player position as string) & linefeed & ((duration of t) as string)
        end tell
        """
        guard let out = run(script)?.stringValue, out != "stopped" else { set(app, nil); return }
        let parts = out.components(separatedBy: "\n")
        guard parts.count >= 5 else { return }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        var duration = num(parts[4])
        if app == .spotify { duration /= 1000 } // Spotify reports milliseconds
        var now = NowPlaying(app: app, title: parts[0], artist: parts[1], playing: parts[2] == "playing",
                             position: num(parts[3]), duration: duration, updatedAt: .now)
        let previous = app == .music ? music : spotify
        if previous?.title == now.title, previous?.artist == now.artist { now.artwork = previous?.artwork }
        set(app, now)
        if now.artwork == nil { loadArtwork(app) }
    }

    private func set(_ app: NowPlaying.App, _ value: NowPlaying?) {
        if app == .music { music = value } else { spotify = value }
    }

    private func loadArtwork(_ app: NowPlaying.App) {
        switch app {
        case .music:
            guard let data = run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data, !data.isEmpty else { return }
            music?.artwork = data
        case .spotify:
            guard let s = run("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                  let url = URL(string: s) else { return }
            let title = spotify?.title
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url), spotify?.title == title else { return }
                spotify?.artwork = data
            }
        }
    }

    /// Runs AppleScript; notes when macOS's Automation permission was refused (error -1743).
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let code = error?[NSAppleScript.errorNumber] as? Int { permissionDenied = code == -1743 }
        else { permissionDenied = false }
        return error == nil ? result : nil
    }
}
