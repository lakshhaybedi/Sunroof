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
