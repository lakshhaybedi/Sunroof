import SwiftUI

/// The Mac's Backspace key sends U+007F, but SwiftUI's `KeyEquivalent.delete` is U+0008 — match both.
func isBackspace(_ c: Character) -> Bool { c == "\u{7F}" || c == "\u{8}" }

extension KeyPress {
    var isBackspace: Bool { Sunroof.isBackspace(key.character) }
}
