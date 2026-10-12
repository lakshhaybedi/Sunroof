import Foundation

/// What a player reports. There's no public system-wide "now playing" API, so only Apple Music and Spotify.
struct NowPlaying: Equatable {
    enum App: String { case music, spotify
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var scriptName: String { self == .music ? "Music" : "Spotify" }
    }

    var app: App
    var title: String
    var artist: String
    var playing: Bool
    var position: Double   // seconds at `updatedAt`
    var duration: Double   // seconds
    var updatedAt: Date
    var artwork: Data? = nil

    func position(at date: Date) -> Double {
        guard playing else { return position }
        return min(duration, position + date.timeIntervalSince(updatedAt))
    }

    /// State from a player's distributed notification (no AppleScript needed). Nil when stopped — Spotify and
    /// Music also send "Stopped" while quitting, and asking them anything then would relaunch them.
    static func from(userInfo: [AnyHashable: Any], app: App, now: Date) -> NowPlaying? {
        let state = userInfo["Player State"] as? String
        guard state == "Playing" || state == "Paused", let title = userInfo["Name"] as? String else { return nil }
        let ms = (userInfo[app == .music ? "Total Time" : "Duration"] as? NSNumber)?.doubleValue ?? 0
        return NowPlaying(app: app, title: title, artist: userInfo["Artist"] as? String ?? "", playing: state == "Playing",
                          position: (userInfo["Playback Position"] as? NSNumber)?.doubleValue ?? 0,
                          duration: ms / 1000, updatedAt: now)
    }

    /// Playing beats paused; both playing → the one started last; neither → the most recently updated.
    static func merge(music: NowPlaying?, spotify: NowPlaying?, lastStarted: App?) -> NowPlaying? {
        switch (music, spotify) {
        case (nil, nil): return nil
        case let (m?, nil): return m
        case let (nil, s?): return s
        case let (m?, s?):
            if m.playing != s.playing { return m.playing ? m : s }
            if m.playing { return lastStarted == .spotify ? s : m }
            return m.updatedAt >= s.updatedAt ? m : s
        }
    }
}
