import SwiftUI

/// Plain-looking button whose whole frame is clickable (not just the glyph's opaque pixels),
/// at least 28×28 pt, with a subtle hover/press highlight so it's clear what you're about to hit.
struct HitButtonStyle: ButtonStyle {
    var minSize: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        HitLabel(configuration: configuration, minSize: minSize)
    }

    private struct HitLabel: View {
        let configuration: Configuration
        let minSize: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(minWidth: minSize, minHeight: minSize)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : hovering ? 0.08 : 0)))
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == HitButtonStyle {
    static var hit: HitButtonStyle { HitButtonStyle() }
}
