import Foundation
import Testing
@testable import BedtimeCore

struct BookTests {
    @Test func titleOnlyAndOptionalContent() throws {
        try BookManifest(title: "Lisek i księżyc").validate()
        let book = BookManifest(title: "Audio", chapters: [BookChapter(audio: "audio/01.mp3"), BookChapter(text: "chapters/02.md"), BookChapter(audio: "audio/03.wav")])
        try book.validate()
        #expect(book.hasAudio)
        #expect(book.hasReading)
        #expect(AudioTrack.tracks(for: book).map(\.path) == ["audio/01.mp3", "audio/03.wav"])
    }
    @Test func invalidLayoutsAndTimestamps() {
        #expect(throws: BookError.self) { try BookManifest(title: " ").validate() }
        #expect(throws: BookError.self) { try BookManifest(title: "Mixed", audio: "audio/all.m4a", chapters: [BookChapter(audio: "audio/one.m4a")]).validate() }
        #expect(throws: BookError.self) { try BookManifest(title: "Bad", audio: "audio/all.m4a", chapters: [BookChapter(startTime: 5), BookChapter(startTime: 3)]).validate() }
        #expect(throws: BookError.self) { try BookManifest(title: "Bad", audio: "audio/all.m4a", chapters: [BookChapter(startTime: 0), BookChapter()]).validate() }
        let chapter = BookChapter()
        #expect(throws: BookError.self) { try BookManifest(title: "Duplicates", chapters: [chapter, chapter]).validate() }
    }
    @Test func timestampChapterSelectionAndSleepBoundaries() throws {
        let chapters = [BookChapter(title: "One", startTime: 0), BookChapter(title: "Two", startTime: 30)]
        let book = BookManifest(title: "Fox", audio: "audio/full.m4a", chapters: chapters)
        try book.validate()
        #expect(AudioTrack.chapter(at: 29, in: book)?.id == chapters[0].id)
        #expect(AudioTrack.chapter(at: 30, in: book)?.id == chapters[1].id)
        #expect(AudioTrack.nextBoundary(after: 5, in: book, duration: 90) == 30)
        #expect(AudioTrack.nextBoundary(after: 35, in: book, duration: 90) == 90)
        #expect(AudioTrack.nextBoundary(after: 5, in: BookManifest(title: "No timestamps", audio: "a.mp3"), duration: 90) == nil)
        let position = PlaybackPosition(bookID: book.id, chapterID: chapters[1].id, seconds: 37.5)
        #expect(try JSONDecoder().decode(PlaybackPosition.self, from: JSONEncoder().encode(position)) == position)
    }
    @Test(arguments: ["../audio.mp3", "/audio.mp3", "x/../a.mp3", "x//a.mp3", ".secret", "a\\b.mp3", "https:audio.mp3"])
    func unsafePaths(_ path: String) {
        #expect(throws: BookError.self) { try SafeBookPath.validate(path) }
    }
    @Test func roundTripAndChecksumFailure() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let folder = workspace.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let chapter = BookChapter(title: "Księżyc", text: "01.md", image: "01.jpg", audio: "01.mp3")
        let book = BookManifest(title: "Łagodna noc", cover: "cover.jpg", chapters: [chapter])
        try JSONEncoder().encode(book).write(to: folder.appendingPathComponent("book.json"))
        for (name, bytes) in [("01.md", "# Księżyc\n\nLisek zasnął."), ("01.jpg", "chapter bytes"), ("cover.jpg", "cover bytes"), ("01.mp3", "audio bytes")] {
            try Data(bytes.utf8).write(to: folder.appendingPathComponent(name))
        }
        try Data("private".utf8).write(to: folder.appendingPathComponent("progress.json"))
        let archive = workspace.appendingPathComponent("Fox.bedtimestory")
        try StoryArchive.create(from: folder, at: archive)
        let destination = workspace.appendingPathComponent("Imported")
        try StoryArchive.extract(archive, to: destination)
        #expect(try BookManifest.load(from: destination, requireAssets: true) == book)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("progress.json").path))
        var bytes = try Data(contentsOf: archive)
        let pattern = Data("audio bytes".utf8)
        let range = try #require(bytes.range(of: pattern))
        bytes[range.lowerBound] ^= 1
        let corrupt = workspace.appendingPathComponent("Corrupt.bedtimestory")
        try bytes.write(to: corrupt)
        let failed = workspace.appendingPathComponent("Failed")
        #expect(throws: BookError.self) { try StoryArchive.extract(corrupt, to: failed) }
        #expect(!FileManager.default.fileExists(atPath: failed.path))
        try bytes.prefix(20).write(to: workspace.appendingPathComponent("Short.bedtimestory"))
        #expect(throws: BookError.self) { try StoryArchive.extract(workspace.appendingPathComponent("Short.bedtimestory"), to: failed) }
    }
    @Test func symlinkAndMissingAssetRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = BookManifest(title: "Missing", audio: "missing.mp3")
        try JSONEncoder().encode(book).write(to: folder.appendingPathComponent("book.json"))
        _ = try BookManifest.load(from: folder)
        #expect(throws: (any Error).self) { _ = try BookManifest.load(from: folder, requireAssets: true) }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: BookError.self) { _ = try SafeBookPath.resolve("escape/file.mp3", inside: folder) }
    }
    @Test func pythonWriterSwiftReaderAndSwiftWriterPythonReader() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repository.appendingPathComponent("skills/bedtime-book-create/scripts/book.py")
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source")
        let archive = workspace.appendingPathComponent("Python.bedtimestory")
        try runPython(script, ["create", "--title", "Śpiący lisek", "--output", source.path, "--archive", archive.path])
        let imported = workspace.appendingPathComponent("Imported")
        try StoryArchive.extract(archive, to: imported)
        #expect(try BookManifest.load(from: imported).title == "Śpiący lisek")
        let swift = workspace.appendingPathComponent("Swift.bedtimestory")
        try StoryArchive.create(from: imported, at: swift)
        try runPython(script, ["validate", swift.path])
        for mutation in ["traversal", "duplicate", "compressed", "symlink", "unsupported"] {
            let bad = workspace.appendingPathComponent(mutation + ".bedtimestory")
            let python = """
            import json, zipfile, stat
            source = json.loads(open(\(String(reflecting: source.appendingPathComponent("book.json").path))).read())
            mode = \(String(reflecting: mutation))
            if mode == 'unsupported': source['formatVersion'] = 2
            with zipfile.ZipFile(\(String(reflecting: bad.path)), 'w', compression=zipfile.ZIP_DEFLATED if mode == 'compressed' else zipfile.ZIP_STORED) as z:
                z.writestr('book.json', json.dumps(source))
                if mode == 'traversal': z.writestr('../escape.txt', 'escape')
                if mode == 'duplicate': z.writestr('BOOK.JSON', '{}')
                if mode == 'symlink':
                    info = zipfile.ZipInfo('link'); info.create_system = 3; info.external_attr = (stat.S_IFLNK | 0o777) << 16; z.writestr(info, '../escape')
            """
            try runCommand(["-c", python])
            let destination = workspace.appendingPathComponent("Failed-" + mutation)
            #expect(throws: (any Error).self) { try StoryArchive.extract(bad, to: destination) }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }
    private func runPython(_ script: URL, _ arguments: [String]) throws { try runCommand([script.path] + arguments) }
    private func runCommand(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

struct StoryTextTests {
    @Test func markdownHeadingsListsAndDuplicateTitle() {
        let text = "## Night\nA **quiet** fox.\n\n- Blanket\n- Moon\n\n1. Rest\n\n### Dream\nSleep."
        let blocks = StoryTextBlock.parse(text, markdown: true, omittingTitle: "Night")
        #expect(blocks.first?.text == "A **quiet** fox.")
        #expect(blocks.filter { if case .list = $0.kind { true } else { false } }.count == 3)
        #expect(blocks.contains { $0.kind == .heading(3) && $0.text == "Dream" })
        #expect(StoryTextBlock.parse("# Literally plain\n\n*not styled*", markdown: false).map(\.text) == ["# Literally plain", "*not styled*"])
    }
}
