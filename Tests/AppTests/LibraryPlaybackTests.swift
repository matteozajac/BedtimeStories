import Foundation
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct LibraryPlaybackTests {
    @Test func indexingOfflineCacheImportAndReplacement() async throws {
        let workspace = try fixtureWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("Library")
        let book = try makeBook(root: root, title: "Good", recordings: [0.5])
        let malformed = root.appendingPathComponent("Malformed")
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: malformed.appendingPathComponent("book.json"))
        let repository = LibraryRepository(cacheRoot: workspace.appendingPathComponent("Cache"))
        let scan = try await repository.scan(root: root)
        #expect(scan.books.count == 1)
        #expect(scan.warnings.count == 1)
        try await repository.keepOffline(book, root: root)
        #expect(await repository.pinnedIDs() == [book.id])
        let exported = try await repository.share(book, root: root)
        defer { try? FileManager.default.removeItem(at: exported) }
        let staged = try await repository.stageImport(exported)
        do {
            try await repository.commitImport(staged, root: root, replacing: false)
            Issue.record("Duplicate import did not require replacement")
        } catch BookError.duplicate { }
        #expect(try BookManifest.load(from: staged.folder).id == book.id)
        try await repository.commitImport(staged, root: root, replacing: true)
        #expect(!FileManager.default.fileExists(atPath: staged.folder.path))
        #expect(try await repository.scan(root: root).books.count == 1)
        try await repository.keepOffline(book, root: root)
        try FileManager.default.removeItem(at: root)
        let offline = try await repository.scan(root: root)
        #expect(offline.isOffline)
        #expect(offline.books.count == 1)
        let cached = try await repository.asset("audio/01.wav", book: book, root: root)
        #expect(FileManager.default.fileExists(atPath: cached.path))
        try await repository.clearUnpinned(protecting: nil)
        #expect(FileManager.default.fileExists(atPath: cached.path))
        try await repository.removeOffline(book.id, protecting: nil)
        #expect(!FileManager.default.fileExists(atPath: cached.path))
    }

    @Test func playerLoadSeekSleepAndIndependentResume() async throws {
        let workspace = try fixtureWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("Library")
        let book = try makeBook(root: root, title: "Audio", recordings: [3, 3])
        let repository = LibraryRepository(cacheRoot: workspace.appendingPathComponent("Cache"))
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let progress = LocalProgress(namespace: "one", defaults: defaults)
        let other = LocalProgress(namespace: "two", defaults: defaults)
        let player = StoryPlayer()
        defer { player.stop() }
        player.play(book: book, chapter: nil, repository: repository, root: root, progress: progress)
        try await wait { !player.loading && (player.playing || player.error != nil) }
        #expect(player.error == nil)
        #expect(player.playing)
        #expect(abs(player.duration - 3) < 0.1)
        player.seek(1)
        player.pause()
        #expect(!player.playing)
        #expect(progress.playback(book.id)?.seconds == 1)
        #expect(other.playback(book.id) == nil)
        player.selectChapter(book.manifest.orderedChapters[1])
        try await wait { !player.loading && (player.playing || player.error != nil) }
        #expect(player.trackIndex == 1)
        player.sleepAtChapterEnd()
        #expect(player.sleepLabel != nil)
        player.seek(2.8)
        try await wait { !player.playing }
        #expect(player.sleepLabel == nil)
        let saved = try #require(progress.playback(book.id))
        player.stop()
        player.restore(book: book, repository: repository, root: root, progress: progress)
        #expect(!player.playing)
        #expect(player.trackIndex == 1)
        #expect(player.elapsed == saved.seconds)
    }

    @Test func automaticChapterAdvanceAndFullBookBoundaries() async throws {
        let workspace = try fixtureWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("Library")
        let book = try makeBook(root: root, title: "Queue", recordings: [0.4, 2])
        let repository = LibraryRepository(cacheRoot: workspace.appendingPathComponent("Cache"))
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let progress = LocalProgress(namespace: "queue", defaults: defaults)
        let player = StoryPlayer()
        defer { player.stop() }
        player.play(book: book, chapter: nil, repository: repository, root: root, progress: progress)
        try await wait { player.trackIndex == 1 && !player.loading && player.playing }
        #expect(player.playing)
        player.pause()
        var full = book
        full.manifest.audio = "audio/02.wav"
        full.manifest.chapters = [BookChapter(title: "A", startTime: 0), BookChapter(title: "B", startTime: 1)]
        player.play(book: full, chapter: full.manifest.orderedChapters[1], repository: repository, root: root, progress: progress)
        try await wait { !player.loading && (player.playing || player.error != nil) }
        #expect(player.error == nil)
        #expect(player.currentChapterID == full.manifest.orderedChapters[1].id)
        #expect(player.canSleepAtChapterEnd)
        player.setSpeed(1.5)
        #expect(player.speed == 1.5)
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(predicate())
    }
    private func fixtureWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func makeBook(root: URL, title: String, recordings: [Double]) throws -> LibraryBook {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("audio"), withIntermediateDirectories: true)
        var chapters: [BookChapter] = []
        for (index, seconds) in recordings.enumerated() {
            let path = String(format: "audio/%02d.wav", index + 1)
            try wave(seconds: seconds).write(to: folder.appendingPathComponent(path))
            chapters.append(BookChapter(title: "Chapter \(index + 1)", audio: path))
        }
        let manifest = BookManifest(title: title, chapters: chapters)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("book.json"))
        return LibraryBook(manifest: manifest, folder: folder)
    }
    private func wave(seconds: Double) -> Data {
        let rate = 8000
        let samples = Int(Double(rate) * seconds)
        var data = Data()
        func put(_ value: UInt32, bytes: Int = 4) { for index in 0..<bytes { data.append(UInt8((value >> (index * 8)) & 255)) } }
        data.append(Data("RIFF".utf8)); put(UInt32(36 + samples * 2)); data.append(Data("WAVEfmt ".utf8))
        put(16); put(1, bytes: 2); put(1, bytes: 2); put(UInt32(rate)); put(UInt32(rate * 2)); put(2, bytes: 2); put(16, bytes: 2)
        data.append(Data("data".utf8)); put(UInt32(samples * 2)); data.append(Data(count: samples * 2))
        return data
    }
}
