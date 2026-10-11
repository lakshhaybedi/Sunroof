import AppKit
import Testing
@testable import Sunroof

@Suite struct FileDropOperationTests {
    let dir = tempDir()

    func touch(_ name: String, in d: URL? = nil) -> URL {
        let url = (d ?? dir).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    @Test func modifierMapping() {
        #expect(FileDropOperation.from([]) == .move)
        #expect(FileDropOperation.from([.option]) == .copy)
        #expect(FileDropOperation.from([.command, .option]) == .alias)
        #expect(FileDropOperation.from([.command]) == .move)
    }

    @Test func uniqueNames() throws {
        #expect(uniqueDestination(for: "a.txt", in: dir).lastPathComponent == "a.txt")
        _ = touch("a.txt")
        #expect(uniqueDestination(for: "a.txt", in: dir).lastPathComponent == "a 2.txt")
        _ = touch("a 2.txt")
        #expect(uniqueDestination(for: "a.txt", in: dir).lastPathComponent == "a 3.txt")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("F"), withIntermediateDirectories: true)
        #expect(uniqueDestination(for: "F", in: dir).lastPathComponent == "F 2")
    }

    @Test func moveCopyAlias() throws {
        let src = tempDir()
        let a = touch("a.txt", in: src)
        let copied = try perform(.copy, a, into: dir)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: copied.path))
        let alias = try perform(.alias, a, into: dir)
        #expect(alias.lastPathComponent == "a 2.txt")
        #expect(try URL(resolvingAliasFileAt: alias).standardizedFileURL.path == a.standardizedFileURL.path)
        let moved = try perform(.move, a, into: dir)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(moved.lastPathComponent == "a 3.txt")
    }

    @Test func moveOntoSameFolderIsNoOp() throws {
        let a = touch("a.txt")
        #expect(try perform(.move, a, into: dir) == a)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.txt"])
    }

    // Review C1: copying a folder into itself (or below itself) must be refused, not recurse.
    @Test func copyFolderIntoItselfRefused() throws {
        let folder = dir.appendingPathComponent("Root")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try perform(.copy, folder, into: folder) }
        #expect(throws: (any Error).self) { try perform(.copy, folder, into: folder.appendingPathComponent("Sub")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Sub"])
    }

    // Review I2: the same-folder no-op must not depend on trailing slashes.
    @Test func sameFolderNoOpWithTrailingSlash() throws {
        let a = touch("a.txt")
        let slashed = URL(filePath: dir.path + "/", directoryHint: .isDirectory)
        #expect(try perform(.move, a, into: slashed).path == a.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.txt"])
    }
}
