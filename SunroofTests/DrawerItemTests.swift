import Foundation
import Testing
@testable import Sunroof

@Suite struct DrawerItemTests {
    func item(_ name: String, dir: Bool = false, kind: String = "Plain Text", added: Double = 0, modified: Double = 0) -> DrawerItem {
        DrawerItem(url: URL(fileURLWithPath: "/x/\(name)"), name: name, isDirectory: dir, kind: kind,
                   dateAdded: Date(timeIntervalSince1970: added), dateModified: Date(timeIntervalSince1970: modified), size: nil)
    }

    @Test func sortByName() {
        let items = ["b.txt", "A.txt", "c 10.txt", "c 9.txt"].map { item($0) }
        #expect(sortItems(items, by: .name, foldersOnTop: false).map(\.name) == ["A.txt", "b.txt", "c 9.txt", "c 10.txt"])
    }

    @Test func sortByKindThenName() {
        let items = [item("b.png", kind: "Image"), item("a.txt", kind: "Text"), item("a.png", kind: "Image")]
        #expect(sortItems(items, by: .kind, foldersOnTop: false).map(\.name) == ["a.png", "b.png", "a.txt"])
    }

    @Test func sortByDateAddedNewestFirst() {
        let items = [item("old", added: 1), item("new", added: 3), item("mid", added: 2)]
        #expect(sortItems(items, by: .dateAdded, foldersOnTop: false).map(\.name) == ["new", "mid", "old"])
    }

    @Test func sortByDateModifiedNewestFirst() {
        let items = [item("old", modified: 1), item("new", modified: 3)]
        #expect(sortItems(items, by: .dateModified, foldersOnTop: false).map(\.name) == ["new", "old"])
    }

    @Test func foldersOnTop() {
        let items = [item("a"), item("z", dir: true)]
        #expect(sortItems(items, by: .name, foldersOnTop: true).map(\.name) == ["z", "a"])
        #expect(sortItems(items, by: .name, foldersOnTop: false).map(\.name) == ["a", "z"])
    }

    @Test func loadReadsAttributes() throws {
        let url = tempDir().appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: url)
        let i = try #require(DrawerItem.load(url))
        #expect(i.name == "hello.txt")
        #expect(i.isDirectory == false)
        #expect(i.size == 5)
    }

    // UX pass: ⇧-click extends from the last clicked item (the anchor), either direction.
    @Test func shiftClickRange() {
        let ids = ["a", "b", "c", "d", "e"].map { URL(fileURLWithPath: "/x/\($0)") }
        #expect(rangeSelection(ids, anchor: ids[3], target: ids[1]) == Set(ids[1...3]))
        #expect(rangeSelection(ids, anchor: nil, target: ids[2]) == [ids[2]])
    }
}
