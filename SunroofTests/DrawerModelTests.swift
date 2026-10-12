import Foundation
import Testing
@testable import Sunroof

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

    // A folder we may read but not change (e.g. Desktop without Files & Folders access): copy instead of failing.
    @Test func moveFallsBackToCopyWhenSourceIsLocked() throws {
        let locked = tempDir()
        let ext = touch("shot.png", in: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let m = model()
        _ = try m.drop([ext], operation: .move)
        #expect(m.items.map(\.name) == ["shot.png"])
        #expect(FileManager.default.fileExists(atPath: ext.path))
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

    @Test func searchIsRecursive() async throws {
        let z = try mkdir("Z")
        touch("deep.txt", in: z)
        let m = model()
        m.query = "deep"
        await m.searchSettled()
        #expect(m.items.map(\.name) == ["deep.txt"])
        m.query = ""
        await m.searchSettled()
        #expect(m.items.map(\.name) == ["Z"])
    }

    // Review I3: URLs the model returns match the listed items exactly (no trailing-slash variants).
    @Test func newFolderURLMatchesListing() throws {
        let m = model()
        let url = try m.newFolder()
        #expect(m.items.map(\.url) == [url])
        let renamed = try m.rename(m.items[0], to: "Projects")
        #expect(m.items.map(\.url) == [renamed])
    }

    // Review I5: after the default folder is trashed and recreated, live updates still work.
    @Test func watcherFollowsRecreatedRoot() async throws {
        let m = model()
        try FileManager.default.moveItem(at: root, to: tempDir().appendingPathComponent("Trashed"))
        m.reload()
        touch("after.txt")
        for _ in 0..<40 where m.items.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(m.items.map(\.name) == ["after.txt"])
    }

    // Review I6: a custom folder that comes back is picked up on the next reload.
    @Test func customRootRecovers() throws {
        try FileManager.default.removeItem(at: root)
        let m = model(isDefault: false)
        #expect(m.rootMissing)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        m.reload()
        #expect(!m.rootMissing)
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

    // Regression: changing the root (Files folder setting) used to recurse forever via didSet under @Observable.
    @Test func changingRootNavigatesToIt() throws {
        let m = model()
        let other = tempDir().appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.appendingPathComponent("o.txt").path, contents: Data())
        m.changeRoot(URL(fileURLWithPath: other.path + "//"), isDefault: false)
        #expect(m.current.path == other.path)
        #expect(m.items.map(\.name) == ["o.txt"])
    }

    // Review I4: a cancelled Files search stops walking the tree.
    @Test func searchStopsWhenCancelled() async throws {
        for i in 0..<50 { touch("f\(i).txt") }
        let r = root
        let t = Task.detached { () -> [URL] in
            withUnsafeCurrentTask { $0?.cancel() }
            return DrawerModel.search("f", in: r)
        }
        #expect(await t.value.isEmpty)
    }
}
