import Foundation

/// What the Clipboard panel needs from Notes for "Send to Note" (keeps the panels decoupled).
@MainActor protocol NoteAppending: AnyObject {
    /// The 8 most recently modified notes.
    var recentNoteTitles: [(filename: String, title: String)] { get }
    /// Appends text to a note (nil → a new note titled by the text's first line). Returns the note's filename.
    @discardableResult func append(_ text: String, to filename: String?) -> String
    /// Copies an image into attachments/ and appends it. Returns the note's filename.
    @discardableResult func appendImage(_ png: Data, to filename: String?) -> String
}
