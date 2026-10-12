import Testing
@testable import Sunroof

@Suite struct NoteCleanupTests {
    func clean(_ s: String) -> String { NoteCleanup.clean(s) }

    @Test func bulletsWithNesting() {
        #expect(clean("T\n• one\n  • two\n\t· three\n* four\n– five") == "T\n- one\n  - two\n  - three\n- four\n- five")
    }

    @Test func numberedListsAreRenumbered() {
        #expect(clean("T\n1) a\n3) b\n(4) c") == "T\n1. a\n2. b\n3. c")
        #expect(clean("T\na) x\nb) y") == "T\n1. x\n2. y")
        #expect(clean("T\n1) a\n\n2) b\nprose\n1) again") == "T\n1. a\n\n2. b\nprose\n1. again")
    }

    @Test func checkboxes() {
        #expect(clean("T\n☐ milk\n✔ eggs\n[x] done\n• [ ] later") == "T\n- [ ] milk\n- [x] eggs\n- [x] done\n- [ ] later")
    }

    @Test func headings() {
        #expect(clean("T\n\nGroceries:\n- milk\n\nTODAY\nstuff") == "T\n\n## Groceries\n- milk\n\n## TODAY\nstuff")
        // Not on its own (no blank line before) → left alone.
        #expect(clean("T\nsome text\nNOTE\nmore") == "T\nsome text\nNOTE\nmore")
    }

    @Test func labelsBecomeBold() {
        #expect(clean("T\nName: John\n- Phone: 123") == "T\n**Name:** John\n- **Phone:** 123")
        #expect(clean("T\nhttps://x.com\nThis is a long sentence that has: a colon") == "T\nhttps://x.com\nThis is a long sentence that has: a colon")
    }

    @Test func whitespace() {
        #expect(clean("T  \n\n\n\nbody   \n\n") == "T\n\nbody\n")
    }

    @Test func titleCodeAndMarkdownUntouched() {
        #expect(clean("• title line\nx") == "• title line\nx")
        #expect(clean("T\n```\n• keep\nName: raw\n```") == "T\n```\n• keep\nName: raw\n```")
        let md = "T\n# H\n- [ ] a\n**B:** c\n> quote\n1. one"
        #expect(clean(md) == md)
    }

    @Test func idempotent() {
        let messy = "Trip\n\nPACKING:\n• socks\n  ☐ charger\n1) passport\n4) visa\nHotel: Ritz\n\n\n\nTODO\n✓ book"
        #expect(clean(clean(messy)) == clean(messy))
    }

    // "Name - text" labels (meeting notes) get the name in bold, like "Label: value".
    @Test func dashLabelsBecomeBold() {
        #expect(clean("T\nMarc - How long is it going to take?\nSere – Does the money go to artisans?")
                == "T\n**Marc** - How long is it going to take?\n**Sere** – Does the money go to artisans?")
        #expect(clean("T\nWell-known fact here") == "T\nWell-known fact here")
        #expect(clean("T\nThis is a sentence - with a dash in it") == "T\nThis is a sentence - with a dash in it")
    }

    // A long first line is a paragraph, not a title: clean it like the rest.
    @Test func longFirstLineIsBody() {
        let first = "Marc - How long is it going to take for the whole thing to complete? Don't lose the scope."
        #expect(clean(first + "\nmore") == "**Marc** - How long is it going to take for the whole thing to complete? Don't lose the scope.\nmore")
    }

    @Test func dividerLines() {
        #expect(clean("T\n——————————\n___\n---") == "T\n---\n---\n---")
    }
}
