import Foundation
import Testing
@testable import ShelfScroll

@MainActor
@Suite struct DrawerModelTests {
    let root = tempDir().appendingPathComponent("Drawer")

    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }

    func model(isDefault: Bool = true) -> DrawerModel {
        let m = DrawerModel(root: root, isDefaultRoot: isDefault, trash: { try FileManager.default.removeItem(at: $0) })
        m.arrangeBy = .name
        m.foldersOnTop = true
        return m
    }

    @discardableResult func touch(_ name: String, in dir: URL? = nil) -> URL {
        let url = (dir ?? root).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    func mkdir(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func listsSortedItems() throws {
        touch("b"); touch("a"); _ = try mkdir("Z")
        let m = model()
        #expect(m.items.map(\.name) == ["Z", "a", "b"])
    }

    @Test func navigateIntoAndUp() throws {
        let z = try mkdir("Z")
        let m = model()
        m.open(z)
        // Compare paths: URL equality depends on trailing slashes added when a folder exists.
        #expect(m.current.path == z.path)
        #expect(m.breadcrumbs.map(\.path) == [root.path, z.path])
        m.goUp()
        #expect(m.current.path == root.path)
        m.goUp()
        #expect(m.current.path == root.path)
    }

    @Test func newFolderUnique() throws {
        let m = model()
        #expect(try m.newFolder().lastPathComponent == "untitled folder")
        #expect(try m.newFolder().lastPathComponent == "untitled folder 2")
    }

    @Test func renameClashGetsSuffix() throws {
        touch("a.txt"); touch("b.txt")
        let m = model()
        let a = try #require(m.items.first { $0.name == "a.txt" })
        #expect(try m.rename(a, to: "b.txt").lastPathComponent == "b 2.txt")
    }

    @Test func dropCopiesWithOption() throws {
        let ext = touch("ext.txt", in: tempDir())
        let m = model()
        _ = try m.drop([ext], operation: .copy)
        #expect(FileManager.default.fileExists(atPath: ext.path))
        #expect(m.items.map(\.name) == ["ext.txt"])
    }

    @Test func dropAlreadyHereIsNoOp() throws {
        let a = touch("a.txt")
        let m = model()
        _ = try m.drop([a], operation: .move)
        #expect(m.items.map(\.name) == ["a.txt"])
    }

    @Test func trashUsesInjectedTrash() throws {
        let a = touch("a.txt")
        let m = model()
        try m.trash([a])
        #expect(m.items.isEmpty)
    }

    @Test func searchIsRecursive() throws {
        let z = try mkdir("Z")
        touch("deep.txt", in: z)
        let m = model()
        m.query = "deep"
        #expect(m.items.map(\.name) == ["deep.txt"])
        m.query = ""
        #expect(m.items.map(\.name) == ["Z"])
    }

    @Test func defaultRootRecreated() throws {
        let m = model()
        try FileManager.default.removeItem(at: root)
        m.reload()
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(m.rootMissing == false)
    }

    @Test func customRootMissing() throws {
        try FileManager.default.removeItem(at: root)
        let m = model(isDefault: false)
        #expect(m.rootMissing)
        #expect(m.items.isEmpty)
    }
}
