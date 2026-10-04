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
        try await editor.persist()
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

    @Test func existingBookEditingPreservesIdentityMediaAndOfflinePin() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var original = try await store.create(); original.title = "The Fox"
        original.readingWordsPerMinute = 140; original.illustrationGuide = "A little red fox, a blue scarf, warm pastel colors."
        original.chapters[0].text = "The fox came home."
        original.cover = try await store.addImage(Data("original picture".utf8), draftID: original.id)
        let recording = root.appendingPathComponent("voice.wav"); try wave().write(to: recording)
        original.chapters[0].audio = try await store.addAudio(recording, draftID: original.id).path
        try await store.save(original)
        let folder = root.appendingPathComponent("Library"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let repo = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"))
        try await repo.commitImport(store.stageBook(original), root: folder, replacing: false)
        let book = try #require(try await repo.scan(root: folder).books.first)
        try await repo.keepOffline(book, root: folder)
        let checkout = try await repo.checkout(book, root: folder)
        let draft = try await store.createEditingDraft(checkout); await repo.discardImport(checkout.book)
        #expect(draft.id != book.id && draft.manifest.id == book.id)
        #expect(draft.chapters[0].id == original.chapters[0].id)
        let editor = BookEditorModel(draft: draft, store: store)
        editor.draft.title = "The Fox Returns"; editor.draft.chapters[0].text += " He found a warm blanket."
        editor.addChapter(); editor.draft.chapters[1].text = "Everyone slept peacefully."
        #expect(await editor.setAudio(recording, chapterID: editor.draft.chapters[1].id))
        let staged = try await store.stageBook(editor.draft)
        try await repo.commitEdit(staged, source: try #require(draft.source), root: folder)
        let updated = try #require(try await repo.scan(root: folder).books.first)
        #expect(updated.id == book.id && updated.manifest.title == "The Fox Returns")
        #expect(updated.manifest.orderedChapters[0].id == book.manifest.orderedChapters[0].id)
        #expect(updated.manifest.cover == book.manifest.cover)
        #expect(updated.manifest.illustrationGuide == original.illustrationGuide && updated.manifest.readingWordsPerMinute == 140)
        #expect(updated.manifest.orderedChapters[0].audio == book.manifest.orderedChapters[0].audio)
        #expect(updated.manifest.orderedChapters[1].audio != nil)
        #expect(await repo.pinnedIDs().contains(book.id))
        try FileManager.default.removeItem(at: folder)
        for path in updated.manifest.assetPaths {
            let cached = try await repo.asset(path, book: updated, root: folder)
            #expect(FileManager.default.fileExists(atPath: cached.path))
        }
        let textPath = try #require(updated.manifest.orderedChapters[0].text)
        let cachedText = try await repo.asset(textPath, book: updated, root: folder)
        #expect(try String(contentsOf: cachedText, encoding: .utf8) == editor.draft.chapters[0].text)
    }

    @Test func concurrentTextEditIsRejectedAndCanBeSavedAsNewBook() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var original = try await store.create(); original.title = "Original"; original.chapters[0].text = "A fox sleeps."
        try await store.save(original)
        let folder = root.appendingPathComponent("Library"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let repo = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"))
        try await repo.commitImport(store.stageBook(original), root: folder, replacing: false)
        let book = try #require(try await repo.scan(root: folder).books.first)
        let checkout = try await repo.checkout(book, root: folder)
        var edited = try await store.createEditingDraft(checkout); await repo.discardImport(checkout.book)
        edited.title = "My Version"; edited.chapters[0].text = "A fox dreams."
        try await store.save(edited)
        let text = try SafeBookPath.resolve(try #require(book.manifest.orderedChapters[0].text), inside: book.folder)
        let date = try text.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try Data("A dog sleeps.".utf8).write(to: text)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: text.path) }
        let staged = try await store.stageBook(edited)
        do { try await repo.commitEdit(staged, source: try #require(edited.source), root: folder); Issue.record("Concurrent changes were overwritten") }
        catch BookError.editConflict { }
        await repo.discardImport(staged)
        #expect(try String(contentsOf: text, encoding: .utf8) == "A dog sleeps.")
        #expect(try await store.load(edited.id).title == "My Version")
        edited.source = nil
        try await repo.commitImport(store.stageBook(edited), root: folder, replacing: false)
        #expect(try await repo.scan(root: folder).books.count == 2)
    }

    @Test func discardRestoresDraftAndDoesNotRecreateDiscardedCheckout() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        var original = try await store.create(); original.title = "Keep Me"; try await store.save(original)
        let editor = BookEditorModel(draft: original, store: store)
        #expect(!editor.hasChanges)
        editor.draft.title = "Discard Me"; #expect(editor.hasChanges)
        try await editor.persist()
        #expect(editor.hasChanges)
        #expect(await editor.discardAndClose())
        #expect(try await store.load(original.id).title == "Keep Me")
        var editing = try await store.create(); editing.source = BookEditSource(bookID: UUID(), libraryRoot: root, fingerprint: "original")
        try await store.save(editing)
        let checkout = BookEditorModel(draft: editing, store: store)
        checkout.draft.title = "Unsaved Library Edit"
        #expect(await checkout.discardAndClose())
        let lateRecording = root.appendingPathComponent("late.wav"); try wave().write(to: lateRecording)
        #expect(await checkout.setAudio(lateRecording, chapterID: editing.chapters[0].id) == false)
        #expect(try await store.list().map(\.id) == [original.id])
    }

    @Test func fullBookRecordingAndTimestampsSurviveEditingUntilExplicitReplacement() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        var draft = try await store.create(); draft.title = "Narrated Book"
        let recording = root.appendingPathComponent("voice.wav"); try wave().write(to: recording)
        draft.audio = try await store.addAudio(recording, draftID: draft.id).path
        draft.chapters[0].text = "Good night."; draft.chapters[0].startTime = 0
        try await store.save(draft)
        let editor = BookEditorModel(draft: draft, store: store)
        editor.draft.chapters[0].text += " Sleep well."
        let staged = try await store.stageBook(editor.draft)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        #expect(staged.manifest.audio == draft.audio && staged.manifest.orderedChapters[0].startTime == 0)
        #expect(await editor.setAudio(recording, chapterID: draft.chapters[0].id) == false)
        #expect(editor.draft.audio == draft.audio)
        #expect(await editor.setFullAudio(recording))
        #expect(editor.draft.audio != draft.audio && editor.draft.chapters[0].startTime == nil)
        editor.removeFullNarration()
        #expect(await editor.setAudio(recording, chapterID: draft.chapters[0].id))
        #expect(editor.draft.manifest.audio == nil && editor.draft.manifest.orderedChapters[0].audio != nil)
    }

    @Test func generatedNarrationAttachesEveryChapterAtomicallyAndPreservesExportFormat() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "Generated Narration"
        draft.chapters[0].text = "A fox slept."
        draft.chapters.append(DraftChapter(title: "Morning", text: "The sun rose."))
        let recording = root.appendingPathComponent("voice.wav"); try wave().write(to: recording)
        draft.audio = try await store.addAudio(recording, draftID: draft.id).path
        draft.chapters[0].startTime = 0; draft.chapters[1].startTime = 0.5
        try await store.save(draft)
        let editor = BookEditorModel(draft: draft, store: store)
        let outputs = Dictionary(uniqueKeysWithValues: draft.chapters.map { ($0.id, recording) })
        #expect(await editor.setGeneratedAudio(outputs, expectedSnapshot: draft))
        let restored = try await store.load(draft.id)
        #expect(restored.audio == nil && restored.chapters.allSatisfy { $0.audio != nil && $0.startTime == nil })
        #expect(restored.chapters.map(\.id) == draft.chapters.map(\.id))
        let staged = try await store.stageBook(restored)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let manifest = try BookManifest.load(from: staged.folder, requireAssets: true)
        #expect(AudioTrack.tracks(for: manifest).count == 2)
        #expect(manifest.assetPaths.allSatisfy { !$0.contains("Consent") && !$0.contains("Reference") })
    }

    @Test func failedGeneratedBatchAndStaleSnapshotKeepOriginalNarration() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "Preserve Me"
        draft.chapters[0].text = "Good night."; draft.chapters.append(DraftChapter(text: "Sleep well."))
        let recording = root.appendingPathComponent("voice.wav"); try wave().write(to: recording)
        draft.audio = try await store.addAudio(recording, draftID: draft.id).path
        try await store.save(draft)
        let editor = BookEditorModel(draft: draft, store: store)
        let invalid = root.appendingPathComponent("broken.wav"); try Data("invalid".utf8).write(to: invalid)
        #expect(await editor.setGeneratedAudio([draft.chapters[0].id: recording, draft.chapters[1].id: invalid], expectedSnapshot: draft) == false)
        #expect(editor.draft.hasSameContent(as: draft))
        #expect(try await store.load(draft.id).hasSameContent(as: draft))
        #expect(await editor.setGeneratedAudio([draft.chapters[0].id: recording], expectedSnapshot: draft) == false)
        editor.draft.chapters[0].text = "A new ending."
        #expect(await editor.setGeneratedAudio(Dictionary(uniqueKeysWithValues: draft.chapters.map { ($0.id, recording) }), expectedSnapshot: draft) == false)
        #expect(editor.draft.audio == draft.audio && editor.draft.chapters[0].text == "A new ending.")
    }

    @Test func voiceEnrollmentConvertsBoundedAudioToPrivatePCM24kWave() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("sample.wav")
        try wave(seconds: 10).write(to: source)
        let prepared = try await VoiceEnrollmentAudio.shared.prepare(source, userID: "test-owner", consent: false)
        defer { try? FileManager.default.removeItem(at: prepared) }
        let bytes = try Data(contentsOf: prepared)
        #expect(String(data: bytes.prefix(4), encoding: .utf8) == "RIFF")
        #expect(bytes[24..<28] == Data([0xC0, 0x5D, 0, 0]))
        #expect(bytes[22..<24] == Data([1, 0]) && bytes[34..<36] == Data([16, 0]))
        #expect(bytes.count >= 479_000 && bytes.count <= 480_100)
        #expect(Double(bytes.count - 44) / 48_000 >= 10)
        #expect(prepared.path.contains("CloudVoiceEnrollment") && !prepared.path.contains("Books"))
        try wave(seconds: 1).write(to: source)
        await #expect(throws: BookError.self) { try await VoiceEnrollmentAudio.shared.prepare(source, userID: "test-owner", consent: false) }
        try wave(seconds: 31).write(to: source)
        await #expect(throws: BookError.self) { try await VoiceEnrollmentAudio.shared.prepare(source, userID: "test-owner", consent: false) }
    }

    @Test func unresolvedNarrationRequestRetriesArePrivateAndIdempotent() throws {
        let owner = "ReceiptOwner-\(UUID().uuidString)"
        let otherOwner = "ReceiptOwner-\(UUID().uuidString)"
        defer {
            NarrationRequestReceipt.removePrivateData(uid: owner)
            NarrationRequestReceipt.removePrivateData(uid: otherOwner)
        }
        let draftID = UUID()
        let hash = String(repeating: "a", count: 64)
        func request(_ uid: String? = nil, voice: String = "voice-one", preview: Bool = false) throws -> String {
            try NarrationRequestReceipt.requestID(uid: uid ?? owner, draftID: draftID, snapshotHash: hash, voiceID: voice, preview: preview)
        }
        let original = try request()
        #expect(UUID(uuidString: original) != nil)
        #expect(try request() == original)
        let other = try request(otherOwner)
        #expect(other != original)
        #expect(try request(voice: "voice-two") != original)
        #expect(try request(preview: true) != original)
        NarrationRequestReceipt.confirm(uid: otherOwner, requestID: original)
        #expect(try request(otherOwner) == other)
        NarrationRequestReceipt.confirm(uid: owner, requestID: original)
        let confirmedReplacement = try request()
        #expect(confirmedReplacement != original && UUID(uuidString: confirmedReplacement) != nil)
        NarrationRequestReceipt.removePrivateData(uid: owner)
        #expect(try request() != confirmedReplacement)
        #expect(try request(otherOwner) == other)
    }

    @Test func accountSwitchAndCancellationCannotAttachGeneratedNarration() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "Private Narration"
        draft.chapters[0].text = "A fox sleeps."
        draft.chapters.append(DraftChapter(text: "Morning comes."))
        let recording = root.appendingPathComponent("voice.wav"); try wave().write(to: recording)
        draft.audio = try await store.addAudio(recording, draftID: draft.id).path
        try await store.save(draft)
        let previousAudio = try await store.mediaURL(try #require(draft.audio), draftID: draft.id)
        let mediaDirectory = previousAudio.deletingLastPathComponent()
        let previousFiles = Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path))
        let editor = BookEditorModel(draft: draft, store: store)
        let outputs = Dictionary(uniqueKeysWithValues: draft.chapters.map { ($0.id, recording) })
        var currentAccount = "owner-A"
        var accountSwitch: Task<Void, Never>?
        var observedAccountChange = false
        let authorization: @MainActor () -> Bool = {
            if accountSwitch == nil {
                // The switch runs as soon as audio preparation yields the main actor.
                accountSwitch = Task { @MainActor in currentAccount = "owner-B" }
            }
            if currentAccount != "owner-A" { observedAccountChange = true }
            return currentAccount == "owner-A"
        }
        #expect(await editor.setGeneratedAudio(outputs, expectedSnapshot: draft, authorized: authorization) == false)
        await accountSwitch?.value
        #expect(observedAccountChange)
        #expect(editor.draft.hasSameContent(as: draft))
        #expect(try await store.load(draft.id).hasSameContent(as: draft))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path)) == previousFiles)
        #expect(await editor.setGeneratedAudio(outputs, expectedSnapshot: draft, authorized: { false }) == false)
        let cancelled = Task { await editor.setGeneratedAudio(outputs, expectedSnapshot: draft) }
        cancelled.cancel()
        #expect(await cancelled.value == false)
        #expect(try await store.load(draft.id).hasSameContent(as: draft))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path)) == previousFiles)
    }

    @Test(arguments: [false, true])
    func cancellationOrAccountChangeAfterAudioDiskWriteRestoresPreviousNarration(cancelTask: Bool) async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "Saved Narration"
        draft.chapters[0].text = "A fox sleeps under the stars."
        let recording = root.appendingPathComponent("voice.wav"); try wave().write(to: recording)
        draft.audio = try await store.addAudio(recording, draftID: draft.id).path
        try await store.save(draft)
        let originalAudio = try await store.mediaURL(try #require(draft.audio), draftID: draft.id)
        let mediaDirectory = originalAudio.deletingLastPathComponent()
        let originalFiles = Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path))
        let editor = BookEditorModel(draft: draft, store: store)
        var checks = 0
        let attachment = Task { @MainActor in
            await editor.setGeneratedAudio([draft.chapters[0].id: recording], expectedSnapshot: draft) {
                checks += 1
                // Initial admission, chapter copy, pre-write, then post-write.
                if checks == 4 {
                    if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
                    return cancelTask
                }
                return true
            }
        }
        #expect(await attachment.value == false)
        #expect(checks == 4)
        #expect(editor.draft.hasSameContent(as: draft))
        let recovered = try await BookDraftStore(root: root.appendingPathComponent("Drafts")).load(draft.id)
        #expect(recovered.hasSameContent(as: draft))
        #expect(FileManager.default.fileExists(atPath: originalAudio.path))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path)) == originalFiles)
    }

    @Test func closeKeepsEditingDraftAvailableForBackgroundNarrationReview() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "The Fox"; draft.chapters[0].text = "The fox sleeps."
        draft.source = BookEditSource(bookID: UUID(), libraryRoot: root, fingerprint: "original")
        try await store.save(draft)
        let center = OperationCenter(directory: root.appendingPathComponent("Operations"), systemEnabled: false)
        center.changedOwner("alice")
        let operation = center.begin(kind: .narration, title: draft.title, subtitle: "Creating", destination: .narration(draft.id), ownerID: "alice")
        center.attachRemote(operation, remoteID: "narration-job"); center.update(operation, state: .running)
        let editor = BookEditorModel(draft: draft, store: store, operationCenter: center)
        editor.draft.title = "The Fox Returns"
        #expect(await editor.close())
        #expect((try? await store.load(draft.id))?.title == "The Fox Returns")
        #expect(center.operations.first { $0.id == operation }?.state == .running)
        center.update(operation, state: .ready)
        center.routeNotification(operationID: "narration-job", ownerID: "alice")
        for _ in 0..<20 { await Task.yield() }
        #expect(center.requestedDestination == .narration(draft.id))
        #expect((try? await store.load(draft.id)) != nil)
    }

    @Test func explicitDiscardRetiresActiveAndCompletedDraftOperationsBeforeDeletingCheckout() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "The Fox"; draft.chapters[0].text = "The fox sleeps."
        let bookID = UUID(); draft.source = BookEditSource(bookID: bookID, libraryRoot: root, fingerprint: "original")
        try await store.save(draft)
        let directory = root.appendingPathComponent("Operations")
        let center = OperationCenter(directory: directory, systemEnabled: false); center.changedOwner("alice")
        let active = center.begin(kind: .narration, title: draft.title, subtitle: "Creating", destination: .narration(draft.id), ownerID: "alice")
        center.attachRemote(active, remoteID: "active-job"); center.update(active, state: .running)
        let ready = center.begin(kind: .voicePreview, title: draft.title, subtitle: "Preview", destination: .draft(draft.id), ownerID: "alice")
        center.attachRemote(ready, remoteID: "ready-job"); center.update(ready, state: .ready)
        let unrelated = center.begin(kind: .narration, title: "Another Book", subtitle: "Creating", destination: .narration(UUID()), ownerID: "alice")
        let editor = BookEditorModel(draft: draft, store: store, operationCenter: center)
        #expect(await editor.discardAndClose())
        // A queued second activation must not remove the durable discard marker.
        #expect(await editor.discardAndClose() == false)
        #expect((try? await store.load(draft.id)) == nil)
        for id in [active, ready] {
            #expect(center.operations.first { $0.id == id }?.state == .cancelled)
            #expect(center.operations.first { $0.id == id }?.hiddenFromHistory == true)
            #expect(center.operations.first { $0.id == id }?.destination == .book(bookID))
            #expect(!center.shouldReconcileRemote(id, state: "processing"))
            #expect(!center.shouldReconcileRemote(id, state: "ready"))
        }
        #expect(center.operations.first { $0.id == unrelated }?.state == .queued)
        #expect(center.banner == nil)
        center.clearHistory()
        let restored = OperationCenter(directory: directory, systemEnabled: false); restored.changedOwner("alice")
        restored.routeNotification(operationID: "active-job", ownerID: "alice")
        for _ in 0..<20 { await Task.yield() }
        #expect(restored.requestedDestination == .book(bookID))
        let replay = restored.begin(kind: .narration, title: draft.title, subtitle: "Recovered", destination: .narration(draft.id), ownerID: "alice")
        restored.attachRemote(replay, remoteID: "late-job")
        restored.update(replay, state: .ready, destination: .narration(draft.id))
        #expect(restored.operations.first { $0.id == replay }?.state == .cancelled)
        #expect(restored.operations.first { $0.id == replay }?.destination == .book(bookID))
        #expect(restored.operations.first { $0.id == replay }?.hiddenFromHistory == true)
        #expect(restored.banner == nil)
    }

    @Test func failedDiscardKeepsCancelledReceiptsButAllowsDraftSaveAndNewNarration() async throws {
        let root = workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        var draft = try await store.create(); draft.title = "The Fox"; draft.chapters[0].text = "The fox sleeps."
        draft.source = BookEditSource(bookID: UUID(), libraryRoot: root, fingerprint: "original")
        try await store.save(draft)
        let center = OperationCenter(directory: root.appendingPathComponent("Operations"), systemEnabled: false); center.changedOwner("alice")
        let old = center.begin(kind: .narration, title: draft.title, subtitle: "Creating", destination: .narration(draft.id), ownerID: "alice")
        center.attachRemote(old, remoteID: "old-job")
        let editor = BookEditorModel(draft: draft, store: store, operationCenter: center)
        // An externally missing folder makes the real atomic removal fail.
        try await store.remove(draft.id)
        #expect(await editor.discardAndClose() == false)
        #expect(editor.message != nil)
        #expect(center.operations.first { $0.id == old }?.state == .cancelled)
        #expect(await editor.close())
        #expect((try? await store.load(draft.id)) != nil)
        let fresh = center.begin(kind: .narration, title: draft.title, subtitle: "Creating", destination: .narration(draft.id), ownerID: "alice")
        #expect(center.operations.first { $0.id == fresh }?.state == .queued)
        #expect(center.operations.first { $0.id == fresh }?.hiddenFromHistory != true)
    }

    private func workspace() -> URL { URL.temporaryDirectory.appendingPathComponent("CreatorTest-\(UUID().uuidString)") }
    private func wave(seconds: Int = 1) -> Data {
        var data = Data()
        func put(_ value: UInt32, bytes: Int = 4) { for index in 0..<bytes { data.append(UInt8((value >> (index * 8)) & 255)) } }
        data.append(Data("RIFF".utf8)); put(UInt32(16_000 * seconds + 36)); data.append(Data("WAVEfmt ".utf8))
        put(16); put(1, bytes: 2); put(1, bytes: 2); put(8_000); put(16_000); put(2, bytes: 2); put(16, bytes: 2)
        data.append(Data("data".utf8)); put(UInt32(16_000 * seconds)); data.append(Data(count: 16_000 * seconds))
        return data
    }
}
