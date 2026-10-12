import SwiftUI

struct MusicWidget: View {
    let model: MusicModel
    let size: WidgetSize
    @Environment(AppSettings.self) private var settings
    @State private var hovering = false
    /// Where the playhead is being dragged to (0…1), while scrubbing.
    @State private var scrub: Double?
    @State private var searching = false
    @State private var query = ""
    @State private var results: [MusicSearchResult] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if let np = model.current {
                if size == .small { small(np) } else { medium(np) }
            } else if model.permissionDenied {
                AccessPrompt(symbol: "music.note", text: "Allow Sunroof to control Music / Spotify", button: "Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            } else {
                notPlaying
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop }
        .onHover { hovering = $0 }
    }

    /// The album art, blurred, behind the widget (pink when nothing's playing).
    @ViewBuilder private var backdrop: some View {
        if let data = model.current?.artwork, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill().blur(radius: 30).opacity(0.55)
        } else {
            LinearGradient(colors: [Color.pink.opacity(0.3), Color.purple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func artwork(_ np: NowPlaying, side: CGFloat) -> some View {
        Group {
            if let data = np.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.accentColor.opacity(0.7), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: side * 0.35)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { model.open(np.app) }
        .help("Open \(np.app.scriptName)")
    }

    private func small(_ np: NowPlaying) -> some View {
        ZStack {
            artwork(np, side: 126)
            if hovering || !np.playing {
                Button { model.playPause() } label: {
                    Image(systemName: np.playing ? "pause.fill" : "play.fill").font(.title2).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
        }
        .help("\(np.title) — \(np.artist)")
    }

    private func medium(_ np: NowPlaying) -> some View {
        HStack(spacing: 12) {
            artwork(np, side: 118)
            if searching { searchPanel(np) } else { player(np) }
        }
        .padding(12)
    }

    private func player(_ np: NowPlaying) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(np.title).font(.callout.bold()).lineLimit(1)
                        Text(np.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let fav = np.favorite {
                        Button { model.toggleFavorite() } label: {
                            Image(systemName: fav ? "heart.fill" : "heart").foregroundStyle(fav ? Color.pink : .secondary)
                        }
                        .buttonStyle(HitButtonStyle(minSize: 24)).help(fav ? "Remove from Favorites" : "Favorite")
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let pos = np.position(at: ctx.date)
                    VStack(spacing: 2) {
                        Scrubber(value: scrub ?? (np.duration > 0 ? pos / np.duration : 0)) { f, done in
                            scrub = done ? nil : f
                            if done { model.seek(to: f * np.duration) }
                        }
                        HStack {
                            let shown = scrub.map { $0 * np.duration } ?? pos
                            Text(time(shown)); Spacer(); Text("-" + time(max(0, np.duration - shown)))
                        }
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    Button { model.toggleShuffle() } label: {
                        Image(systemName: "shuffle").font(.caption).foregroundStyle(np.shuffle == true ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(HitButtonStyle(minSize: 24)).help("Shuffle").opacity(np.shuffle == nil ? 0 : 1)
                    Spacer(minLength: 4)
                    Button { model.previous() } label: { Image(systemName: "backward.fill") }.buttonStyle(HitButtonStyle(minSize: 26))
                    Button { model.playPause() } label: { Image(systemName: np.playing ? "pause.fill" : "play.fill").font(.title3) }
                        .buttonStyle(HitButtonStyle(minSize: 30)).padding(.horizontal, 8)
                    Button { model.next() } label: { Image(systemName: "forward.fill") }.buttonStyle(HitButtonStyle(minSize: 26))
                    Spacer(minLength: 4)
                    Button { searching = true; searchFocused = true } label: {
                        Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(HitButtonStyle(minSize: 24)).help(np.app == .spotify ? "Search Spotify" : "Search your Music library")
                }
            }
    }

    /// Search the Music library and play a result (Spotify: opens its own search).
    private func searchPanel(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField(np.app == .spotify ? "Search Spotify" : "Search Music", text: $query)
                    .textFieldStyle(.plain).font(.caption).focused($searchFocused)
                    .onSubmit {
                        if np.app == .spotify { model.searchSpotify(query); closeSearch() }
                        else if let first = results.first { model.play(first); closeSearch() }
                    }
                Button { closeSearch() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(HitButtonStyle(minSize: 20))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 6))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { r in
                        Button { model.play(r); closeSearch() } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.title).font(.caption.bold()).lineLimit(1)
                                Text(r.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if np.app == .spotify && !query.isEmpty {
                        Text("Press ⏎ to search in Spotify").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: query) {
            guard np.app == .music else { return }
            try? await Task.sleep(for: .milliseconds(250)) // wait for typing to pause
            guard !Task.isCancelled else { return }
            results = await model.search(query)
        }
    }

    private func closeSearch() {
        searching = false
        query = ""
        results = []
    }

    private var notPlaying: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.title2).foregroundStyle(.tint)
            Text("Not playing").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let player = MusicWidget.appName(settings.musicPlayerBundleID) {
                    Button("Open \(player)") { model.open(bundleID: settings.musicPlayerBundleID) }.controlSize(.small)
                } else {
                    ForEach([NowPlaying.App.music, .spotify].filter(MusicModel.isInstalled), id: \.self) { app in
                        Button(app == .music ? "Music" : "Spotify") { model.open(app) }.controlSize(.small)
                    }
                }
            }
        }
    }

    /// The display name of an installed app ("YouTube Music"), or nil.
    static func appName(_ bundleID: String) -> String? {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
    }

    private func time(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// A progress bar you can click or drag to move the playhead. Its drag wins over the widget's move-drag.
private struct Scrubber: View {
    let value: Double
    let onChange: (Double, Bool) -> Void // fraction, finished
    @State private var hovering = false

    var body: some View {
        GeometryReader { g in
            let f = max(0, min(value, 1))
            let h: CGFloat = hovering ? 5 : 3
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: h)
                Capsule().fill(Color.primary.opacity(0.8)).frame(width: max(h, g.size.width * f), height: h)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) { // the handle shows on hover and never sets the bar's height
                Circle().fill(.white).frame(width: 9, height: 9).shadow(radius: 1)
                    .offset(x: g.size.width * f - 4.5).opacity(hovering ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { onChange(max(0, min($0.location.x / g.size.width, 1)), false) }
                .onEnded { onChange(max(0, min($0.location.x / g.size.width, 1)), true) })
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .frame(height: 14)
        .help("Drag to move the playhead")
    }
}
