import SwiftUI

struct MusicWidget: View {
    let model: MusicModel
    let size: WidgetSize
    @State private var hovering = false

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
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(np.title).font(.callout.bold()).lineLimit(1)
                    Text(np.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let pos = np.position(at: ctx.date)
                    VStack(spacing: 2) {
                        ProgressView(value: np.duration > 0 ? pos / np.duration : 0).progressViewStyle(.linear)
                        HStack {
                            Text(time(pos)); Spacer(); Text("-" + time(max(0, np.duration - pos)))
                        }
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 14) {
                    Button { model.previous() } label: { Image(systemName: "backward.fill") }.buttonStyle(HitButtonStyle(minSize: 26))
                    Button { model.playPause() } label: { Image(systemName: np.playing ? "pause.fill" : "play.fill").font(.title3) }
                        .buttonStyle(HitButtonStyle(minSize: 30))
                    Button { model.next() } label: { Image(systemName: "forward.fill") }.buttonStyle(HitButtonStyle(minSize: 26))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
    }

    private var notPlaying: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.title2).foregroundStyle(.tint)
            Text("Not playing").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([NowPlaying.App.music, .spotify].filter(MusicModel.isInstalled), id: \.self) { app in
                    Button(app == .music ? "Music" : "Spotify") { model.open(app) }.controlSize(.small)
                }
            }
        }
    }

    private func time(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
