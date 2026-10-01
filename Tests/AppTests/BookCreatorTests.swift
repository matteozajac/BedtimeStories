import Foundation
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct BookCreatorTests {
    @Test func draftsRecoverTextAndRejectStaleAutosave() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        let initial = try await store.create()
        let editor = BookEditorModel(draft: initial, store: store)
        editor.draft.title = "Stories from Home"
        editor.draft.chapters[0].text = "A fox came home.\n\nEveryone was asleep."
        editor.addChapter()
        editor.draft.chapters[1].title = "Morning"
        editor.draft.chapters[1].text = "The birds sang."
        editor.moveChapters(from: [1], to: 0)
        #expect(await editor.close())
        let restored = try await BookDraftStore(root: root).load(initial.id)
        #expect(restored.title == "Stories from Home")
        #expect(restored.chapters[0].title == "Morning")
        #expect(restored.chapters[1].text.contains("fox came home"))
        try await store.save(initial)
        #expect(try await store.load(initial.id) == restored)
        #expect(try await store.list().count == 1)
    }

    @Test func createdBookReadsPlaysAndSharesWithStableChapterOrder() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create()
        draft.title = "  A Family Story  "; draft.author = " Mum "
        draft.chapters[0].text = "# Home\n\nWe made it home."
        draft.chapters.append(DraftChapter(title: "Bedtime", text: "Good night."))
        let source = root.appendingPathComponent("recording.wav")
        try wave().write(to: source)
        let audio = try await store.addAudio(source, draftID: draft.id)
        draft.chapters[1].audio = audio.path; draft.chapters[1].audioDuration = audio.duration
        draft.modifiedAt = Date()
        try await store.save(draft)
        let staged = try await store.stageBook(draft)
        let manifest = try BookManifest.load(from: staged.folder, requireAssets: true)
        #expect(manifest.id == draft.id)
        #expect(manifest.title == "A Family Story")
        #expect(manifest.author == "Mum")
        #expect(manifest.orderedChapters.map(\.id) == draft.chapters.map(\.id))
        #expect(manifest.hasReading && manifest.hasAudio)
        #expect(abs(audio.duration - 1) < 0.1)
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let repository = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"))
        try await repository.commitImport(staged, root: library, replacing: false)
        let scan = try await repository.scan(root: library)
        let book = try #require(scan.books.first)
        let textURL = try await repository.asset(try #require(manifest.orderedChapters[0].text), book: book, root: library)
        #expect(try String(contentsOf: textURL, encoding: .utf8).contains("We made it home."))
        let export = try await repository.share(book, root: library)
        defer { try? FileManager.default.removeItem(at: export) }
        let imported = try await repository.stageImport(export)
        #expect(imported.manifest == manifest)
        await repository.discardImport(imported)
        // Publishing uses a copy: the draft remains recoverable until the editor removes it.
        #expect(try await store.load(draft.id) == draft)
    }

    @Test func failedAudioReplacementAndPublicationKeepDraft() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create()
        draft.title = "Safe Story"
        let source = root.appendingPathComponent("good.wav")
        try wave().write(to: source)
        let editor = BookEditorModel(draft: draft, store: store)
        let chapterID = draft.chapters[0].id
        #expect(await editor.setAudio(source, chapterID: chapterID))
        let previous = try await store.load(draft.id)
        let invalid = root.appendingPathComponent("broken.m4a")
        try Data("not audio".utf8).write(to: invalid)
        #expect(await editor.setAudio(invalid, chapterID: chapterID) == false)
        #expect(editor.draft.chapters[0].audio == previous.chapters[0].audio)
        #expect(try await store.load(draft.id).chapters[0].audio == previous.chapters[0].audio)
        let staged = try await store.stageBook(editor.draft)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let occupied = root.appendingPathComponent("NotAFolder")
        try Data().write(to: occupied)
        let repository = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"))
        do {
            try await repository.commitImport(staged, root: occupied, replacing: false)
            Issue.record("Publication into a file unexpectedly succeeded")
        } catch { }
        #expect(try await store.load(draft.id).chapters[0].audio != nil)
        #expect(FileManager.default.fileExists(atPath: staged.folder.path))
    }

    @Test func blankDraftIsRecoverableButCannotBecomeBook() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        let draft = try await store.create()
        do { _ = try await store.stageBook(draft); Issue.record("Blank title was published") } catch BookError.invalid { }
        #expect(try await store.load(draft.id) == draft)
        var unsafe = draft; unsafe.cover = "../other.jpg"
        do { try await store.save(unsafe); Issue.record("Unsafe draft path was saved") } catch BookError.invalid { }
        #expect(try await store.load(draft.id) == draft)
    }

    private func workspace() -> URL { URL.temporaryDirectory.appendingPathComponent("CreatorTest-\(UUID().uuidString)") }
    private func wave() -> Data {
        var data = Data()
        func put(_ value: UInt32, bytes: Int = 4) { for index in 0..<bytes { data.append(UInt8((value >> (index * 8)) & 255)) } }
        data.append(Data("RIFF".utf8)); put(16_036); data.append(Data("WAVEfmt ".utf8))
        put(16); put(1, bytes: 2); put(1, bytes: 2); put(8_000); put(16_000); put(2, bytes: 2); put(16, bytes: 2)
        data.append(Data("data".utf8)); put(16_000); data.append(Data(count: 16_000))
        return data
    }
}
