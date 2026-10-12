import Foundation

/// What ⌘-click does with a link in a note. Notes can come from anywhere (synced folders, imports), so a link
/// must never run a file or trigger another app's URL action.
enum NoteLinkAction: Equatable {
    case open    // web and mail links
    case reveal  // local files: shown in Finder, never opened
    case ignore  // anything else (app URL schemes, javascript:, …)

    init(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto": self = .open
        case "file": self = .reveal
        default: self = .ignore
        }
    }
}

/// Inline note images load from files on this Mac only — a remote image would tell its server when you read the note.
enum NoteImages {
    static func isAllowed(_ url: URL) -> Bool { url.isFileURL }
}
