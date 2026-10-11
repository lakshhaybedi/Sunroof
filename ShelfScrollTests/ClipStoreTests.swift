import Foundation
import Testing
@testable import ShelfScroll

@MainActor
@Suite struct ClipStoreTests {
    let historyDir = tempDir()
    let favoritesDir = tempDir().appendingPathComponent("Favs")

    func store(limit: Int = 3) -> ClipStore { ClipStore(historyDir: historyDir, favoritesDir: favoritesDir, limit: limit) }

    func clip(_ s: String, app: String = "TextEdit", sensitive: Bool = false) -> Clip {
        Clip(kind: .text, date: .now, text: s, source: ClipSource(bundleID: nil, name: app),
             contentHash: Clip.hash(kind: .text, payload: Data(s.utf8)), isSensitive: sensitive)
    }

    func imageClip(in s: ClipStore) throws -> Clip {
        try FileManager.default.createDirectory(at: s.historyImagesDir, withIntermediateDirectories: true)
        let name = "\(UUID()).png"
        let png = pngData(width: 4, height: 4)
        try png.write(to: s.historyImagesDir.appendingPathComponent(name))
        var c = Clip(kind: .image, date: .now, source: ClipSource(), contentHash: Clip.hash(kind: .image, payload: Data(name.utf8)))
        c.imageFile = name
        return c
    }

    @Test func newestFirst() {
        let s = store()
        s.ingest(clip("a")); s.ingest(clip("b"))
        #expect(s.history.map(\.text) == ["b", "a"])
    }

    @Test func dedupeMovesToTopAndUpdatesSource() {
        let s = store()
        s.ingest(clip("a")); s.ingest(clip("b")); s.ingest(clip("a", app: "Safari"))
        #expect(s.history.map(\.text) == ["a", "b"])
        #expect(s.history[0].source.name == "Safari")
    }

    @Test func limitEvictsOldest() {
        let s = store()
        ["a", "b", "c", "d"].forEach { s.ingest(clip($0)) }
        #expect(s.history.map(\.text) == ["d", "c", "b"])
    }

    @Test func loweringLimitTrims() {
        let s = store()
        ["a", "b", "c"].forEach { s.ingest(clip($0)) }
        s.limit = 1
        #expect(s.history.count == 1)
    }

    @Test func favoriteSurvivesEvictionAndClear() {
        let s = store()
        let a = clip("a")
        s.ingest(a)
        s.toggleFavorite(a)
        ["b", "c", "d"].forEach { s.ingest(clip($0)) }
        s.clearHistory()
        #expect(s.history.isEmpty)
        #expect(s.favorites.map(\.text) == ["a"])
        #expect(s.isFavorite(a))
    }

    @Test func toggleFavoriteRemoves() {
        let s = store()
        let a = clip("a")
        s.toggleFavorite(a); s.toggleFavorite(a)
        #expect(s.favorites.isEmpty)
    }

    @Test func persistsAcrossInstances() async {
        let s = store()
        s.ingest(clip("a"))
        s.toggleFavorite(clip("b"))
        await s.saveNow()
        let t = store()
        #expect(t.history.map(\.text) == ["a"])
        #expect(t.favorites.map(\.text) == ["b"])
    }

    @Test func sensitiveNotPersisted() async {
        let s = store()
        s.ingest(clip("secret", sensitive: true)); s.ingest(clip("a"))
        await s.saveNow()
        #expect(store().history.map(\.text) == ["a"])
    }

    @Test func corruptHistoryStartsEmpty() throws {
        try Data("{not json".utf8).write(to: historyDir.appendingPathComponent("history.json"))
        let s = store()
        #expect(s.history.isEmpty)
        #expect(FileManager.default.fileExists(atPath: historyDir.appendingPathComponent("history.json.corrupt").path))
    }

    @Test func missingImageDropped() async throws {
        let s = store()
        let img = try imageClip(in: s)
        s.ingest(img); s.ingest(clip("a"))
        await s.saveNow()
        try FileManager.default.removeItem(at: s.historyImagesDir.appendingPathComponent(img.imageFile!))
        #expect(store().history.map(\.kind) == [.text])
    }

    @Test func favoritesFolderRecreated() async throws {
        let s = store()
        s.toggleFavorite(clip("a"))
        await s.saveNow()
        try FileManager.default.removeItem(at: favoritesDir)
        s.toggleFavorite(clip("b"))
        await s.saveNow()
        #expect(store().favorites.count == 2)
    }

    @Test func favoriteImageIsCopied() throws {
        let s = store()
        let img = try imageClip(in: s)
        s.ingest(img)
        s.toggleFavorite(img)
        let fav = try #require(s.favorites.first)
        let url = try #require(s.imageURL(for: fav))
        #expect(url.path.hasPrefix(s.favoritesImagesDir.path))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func deleteRemovesImage() throws {
        let s = store()
        let img = try imageClip(in: s)
        s.ingest(img)
        s.delete(img.id)
        #expect(s.history.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: s.historyImagesDir.appendingPathComponent(img.imageFile!).path))
    }

    @Test func updateTextChangesHash() {
        let s = store()
        let a = clip("a")
        s.ingest(a)
        s.updateText(a.id, to: "a2")
        #expect(s.history[0].text == "a2")
        #expect(s.history[0].contentHash != a.contentHash)
    }

    @Test func filterMatchesTextFileNamesAndSource() {
        var f = Clip(kind: .files, date: .now, text: "a.txt", source: ClipSource(), contentHash: "f")
        f.fileURLs = [URL(fileURLWithPath: "/tmp/a.txt")]
        let clips = [clip("hello", app: "Safari"), f, clip("other")]
        #expect(ClipStore.filter(clips, query: "safari").count == 1)
        #expect(ClipStore.filter(clips, query: "A.TXT").first?.kind == .files)
        #expect(ClipStore.filter(clips, query: "").count == 3)
    }
}
