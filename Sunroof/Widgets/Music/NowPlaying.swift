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
    var shuffle: Bool? = nil
    /// Favourited in Apple Music; nil where the player can't tell us (Spotify).
    var favorite: Bool? = nil

    /// The refresh script's reply: title, artist, state, position, duration, shuffle, favourite ("?" = unsupported).
    static func parse(_ out: String, app: App, now: Date) -> NowPlaying? {
        let p = out.components(separatedBy: "\n")
        guard p.count >= 5 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        func flag(_ i: Int) -> Bool? { p.count > i && p[i] != "?" ? p[i] == "true" : nil }
        let duration = num(p[4]) / (app == .spotify ? 1000 : 1) // Spotify reports milliseconds
        return NowPlaying(app: app, title: p[0], artist: p[1], playing: p[2] == "playing", position: num(p[3]),
                          duration: duration, updatedAt: now, shuffle: flag(5), favorite: flag(6))
    }

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

/// A song found in the Apple Music library.
struct MusicSearchResult: Identifiable, Equatable {
    let id: String // persistent ID
    let title: String
    let artist: String

    /// Lines of "id<TAB>title<TAB>artist".
    static func parse(_ out: String) -> [MusicSearchResult] {
        out.components(separatedBy: "\n").compactMap { line in
            let f = line.components(separatedBy: "\t")
            return f.count >= 3 ? MusicSearchResult(id: f[0], title: f[1], artist: f[2]) : nil
        }
    }
}
