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
                let np = NowPlaying.from(userInfo: n.userInfo ?? [:], app: app, now: .now)
                MainActor.assumeIsolated { self?.received(np, from: app) }
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
        Task { await refresh(.music) }
        Task { await refresh(.spotify) }
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    nonisolated static func isRunning(_ app: NowPlaying.App) -> Bool {
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

    /// Jumps to `seconds` in the current track (shown right away, then confirmed by the player).
    func seek(to seconds: Double) {
        guard let np = current else { return }
        let t = max(0, min(seconds, np.duration))
        var moved = np
        moved.position = t
        moved.updatedAt = .now
        set(np.app, moved)
        command("set player position to \(String(format: "%.2f", t))")
    }

    func open(_ app: NowPlaying.App) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func command(_ verb: String) {
        guard let app = current?.app else { return }
        Task {
            _ = await run("tell application \"\(app.scriptName)\" to \(verb)", in: app)
            await refresh(app)
        }
    }

    // MARK: - Reading state

    private func received(_ np: NowPlaying?, from app: NowPlaying.App) {
        guard var np else { set(app, nil); return } // stopped or quitting: never ask the player anything
        if np.playing { lastStarted = app }
        let previous = app == .music ? music : spotify
        if previous?.title == np.title, previous?.artist == np.artist { np.artwork = previous?.artwork }
        set(app, np)
        if app == .music { Task { await refresh(app) } } // Music's notification has no position
        else if np.artwork == nil { Task { await loadArtwork(app) } }
    }

    private func refresh(_ app: NowPlaying.App) async {
        guard Self.isRunning(app) else { set(app, nil); return }
        let script = """
        tell application "\(app.scriptName)"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (player state as string) & linefeed & (player position as string) & linefeed & ((duration of t) as string)
        end tell
        """
        guard let out = await run(script, in: app).string, out != "stopped" else { set(app, nil); return }
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
        if now.artwork == nil { await loadArtwork(app) }
    }

    private func set(_ app: NowPlaying.App, _ value: NowPlaying?) {
        if app == .music { music = value } else { spotify = value }
    }

    private func loadArtwork(_ app: NowPlaying.App) async {
        switch app {
        case .music:
            let title = music?.title
            guard let data = await run("tell application \"Music\" to get raw data of artwork 1 of current track", in: app).data,
                  !data.isEmpty, music?.title == title else { return }
            music?.artwork = data
        case .spotify:
            let title = spotify?.title
            guard let s = await run("tell application \"Spotify\" to get artwork url of current track", in: app).string,
                  let url = URL(string: s),
                  let (data, _) = try? await URLSession.shared.data(from: url), spotify?.title == title else { return }
            spotify?.artwork = data
        }
    }

    private struct ScriptResult: Sendable { var string: String?; var data: Data?; var error: Int? }
    private static let scripts = DispatchQueue(label: "sunroof.music.applescript")

    /// Runs AppleScript on a background queue (a busy player or the Automation prompt never stalls the UI), and only
    /// if the player is still running at that moment (so Sunroof never launches it). Notes a refused permission (-1743).
    private func run(_ source: String, in app: NowPlaying.App) async -> ScriptResult {
        let r = await withCheckedContinuation { (c: CheckedContinuation<ScriptResult, Never>) in
            Self.scripts.async {
                guard Self.isRunning(app) else { return c.resume(returning: ScriptResult(error: 0)) }
                var error: NSDictionary?
                let d = NSAppleScript(source: source)?.executeAndReturnError(&error)
                c.resume(returning: error == nil ? ScriptResult(string: d?.stringValue, data: d?.data)
                                                 : ScriptResult(error: error?[NSAppleScript.errorNumber] as? Int ?? -1))
            }
        }
        if let code = r.error, code != 0 { permissionDenied = code == -1743 } else if r.error == nil { permissionDenied = false }
        return r
    }
}
