import AppKit
import SwiftUI

enum ColorChoice: String, CaseIterable, Codable {
    case system, blue, purple, pink, red, orange, yellow, green, teal, graphite

    var nsColor: NSColor {
        switch self {
        case .system: .controlAccentColor
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .graphite: .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }
    var title: String { self == .system ? "System" : rawValue.capitalized }
}

enum NoteFont: String, CaseIterable, Codable {
    case system, rounded, serif, mono

    var title: String { self == .mono ? "Monospaced" : rawValue.capitalized }

    func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign = switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
        guard let d = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }
}
