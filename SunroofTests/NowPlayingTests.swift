import Foundation
import Testing
@testable import Sunroof

@Suite struct NowPlayingTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func np(_ app: NowPlaying.App, _ playing: Bool, at: Double = 0) -> NowPlaying {
        NowPlaying(app: app, title: "\(app)", artist: "A", playing: playing, position: 30, duration: 200, updatedAt: t0.addingTimeInterval(at))
    }

    @Test func playingBeatsPaused() {
        #expect(NowPlaying.merge(music: np(.music, false), spotify: np(.spotify, true), lastStarted: .music)?.app == .spotify)
    }

    @Test func bothPlayingLastStartedWins() {
        #expect(NowPlaying.merge(music: np(.music, true), spotify: np(.spotify, true), lastStarted: .music)?.app == .music)
        #expect(NowPlaying.merge(music: np(.music, true), spotify: np(.spotify, true), lastStarted: .spotify)?.app == .spotify)
    }

    @Test func neitherPlayingShowsMostRecentlyUpdated() {
        #expect(NowPlaying.merge(music: np(.music, false, at: 5), spotify: np(.spotify, false, at: 1), lastStarted: nil)?.app == .music)
        #expect(NowPlaying.merge(music: nil, spotify: nil, lastStarted: nil) == nil)
    }

    @Test func progressAdvancesOnlyWhilePlaying() {
        #expect(np(.music, true).position(at: t0.addingTimeInterval(10)) == 40)
        #expect(np(.music, false).position(at: t0.addingTimeInterval(10)) == 30)
        #expect(np(.music, true).position(at: t0.addingTimeInterval(1_000)) == 200) // clamped
    }

    // Review I2: state comes from the notification itself; "Stopped" (also sent while quitting) means nothing playing.
    @Test func fromNotification() {
        let info: [AnyHashable: Any] = ["Name": "Song", "Artist": "Band", "Player State": "Playing", "Total Time": 200_000]
        let np = NowPlaying.from(userInfo: info, app: .music, now: t0)
        #expect(np?.title == "Song" && np?.playing == true && np?.duration == 200)
        let spotify: [AnyHashable: Any] = ["Name": "S", "Artist": "A", "Player State": "Paused", "Duration": 180_000, "Playback Position": 12.5]
        #expect(NowPlaying.from(userInfo: spotify, app: .spotify, now: t0)?.position == 12.5)
        #expect(NowPlaying.from(userInfo: ["Player State": "Stopped"], app: .spotify, now: t0) == nil)
    }
}
