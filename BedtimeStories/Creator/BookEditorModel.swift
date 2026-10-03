import Foundation
import MZAppFoundation
import Observation
import SwiftUI
import UIKit

@Observable @MainActor
final class BookEditorModel {
    var draft: BookDraft {
        didSet {
            if !oldValue.hasSameContent(as: draft) {
                changed()
            }
        }
    }
    var message: String?
    private(set) var working = false
    private(set) var saved = true
    var conflict = false
    private var baseline: BookDraft
    private var baselineAvailable = true
    let store: BookDraftStore
    @ObservationIgnored private var autosave: Task<Void, Never>?
    @ObservationIgnored private var closing = false
    @ObservationIgnored private var changeCountSincePersist = 0
    @ObservationIgnored private var loggedUnsavedChanges = false
    @ObservationIgnored private let logger: any AppLogging

    init(draft: BookDraft, store: BookDraftStore, logger: any AppLogging = AppLog.logger) {
        self.draft = draft; baseline = draft; self.store = store; self.logger = logger
    }

    var hasChanges: Bool { (isEditingBook && !baselineAvailable) || !draft.hasSameContent(as: baseline) }
    var isEditingBook: Bool { draft.source != nil }
    var readingPace: Int {
        get { draft.readingWordsPerMinute ?? StoryReadingLength.defaultWordsPerMinute }
        set { draft.readingWordsPerMinute = newValue }
    }

    private var diagnosticFields: [String: TelemetryValue] {
        var fields: [String: TelemetryValue] = ["draft_id": .string(draft.id.uuidString), "editing_existing_book": .bool(isEditingBook)]
        if let source = draft.source { fields["book_id"] = .string(source.bookID.uuidString) }
        return fields
    }

    func loadBaseline() async {
        guard isEditingBook else { return }
        let context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "editing_baseline_load")
        logger.trace("Editing baseline load started", category: "creator", metadata: context.metadata)
        do {
            if let original = try await store.baseline(draft.id) {
                baseline = original
                logger.trace("Editing baseline load completed", category: "creator", metadata: context.metadata)
            }
            else {
                baselineAvailable = false
                logger.warning("Editing baseline is missing; library conflict protection remains active", category: "creator", metadata: context.metadata)
            }
        } catch {
            logger.error("Editing baseline load failed", error: error, category: "creator", metadata: context.metadata)
            baselineAvailable = false; message = String(localized: "The original editing copy could not be opened. Your library book is unchanged.")
        }
    }

    func changed() {
        guard !closing else { return }
        draft.modifiedAt = Date()
        changeCountSincePersist += 1
        if !loggedUnsavedChanges {
            loggedUnsavedChanges = true
            logger.trace("Draft changes awaiting persistence", category: "creator", metadata: diagnosticFields.merging(["chapter_count": .integer(draft.chapters.count)]) { _, new in new })
        }
        saved = false
        let snapshot = draft
        autosave?.cancel()
        autosave = Task { [weak self, store] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                try await store.save(snapshot)
                guard let self, self.draft.modifiedAt == snapshot.modifiedAt else { return }
                self.saved = true
            } catch is CancellationError { }
            catch {
                self?.logger.error("Draft autosave failed", error: error, category: "creator", metadata: self?.diagnosticFields ?? [:])
                self?.message = String(localized: "Your draft could not be saved. Keep the editor open and try again.")
            }
        }
    }

    func persist(operationID: String = UUID().uuidString) async throws {
        guard !closing else { return }
        let pending = autosave
        pending?.cancel()
        await pending?.value
        saved = false
        draft.modifiedAt = Date()
        let snapshot = draft
        var context = BookOperationDiagnostics(operationID: operationID, bookID: draft.source?.bookID, draftID: draft.id, phase: "draft_explicit_persist")
        context.details["changes_since_persist"] = .integer(changeCountSincePersist)
        context.details["chapter_count"] = .integer(draft.chapters.count)
        logger.trace("Draft persistence started", category: "creator", metadata: context.metadata)
        do { try await store.save(snapshot, context: context) }
        catch {
            let failure = BookOperationFailure.preserving(error, context: context)
            await store.flushDiagnosticLogs()
            throw failure
        }
        await store.flushDiagnosticLogs()
        if draft == snapshot { saved = true; changeCountSincePersist = 0; loggedUnsavedChanges = false }
        logger.log(LogEntry("Draft persistence completed", level: .debug, category: "creator", metadata: context.metadata))
    }

    func discardAndClose() async -> Bool {
        guard !working else { return false }
        working = true
        defer { working = false }
        let context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "draft_discard")
        logger.trace("Draft discard started", category: "creator", metadata: context.metadata)
        closing = true
        autosave?.cancel()
        await autosave?.value
        do {
            if isEditingBook || baseline.isEmpty { try await store.remove(draft.id) }
            else {
                var original = baseline; original.modifiedAt = Date()
                try await store.save(original, context: context)
            }
            await store.flushDiagnosticLogs()
            logger.trace("Draft discard completed", category: "creator", metadata: context.metadata)
            return true
        }
        catch {
            let failureEntry = context.failureEntry("Draft discard failed", error: error, category: "creator")
            await store.flushDiagnosticLogs()
            logger.log(failureEntry)
            closing = false; message = String(localized: "Your draft could not be saved. Keep the editor open and try again."); return false
        }
    }

    func addChapter() {
        clearChapterTimes(); draft.chapters.append(DraftChapter())
        logger.trace("Draft chapter added", category: "creator", metadata: diagnosticFields.merging(["chapter_count": .integer(draft.chapters.count)]) { _, new in new })
    }
    func deleteChapters(at offsets: IndexSet) {
        clearChapterTimes(); draft.chapters.remove(atOffsets: offsets)
        logger.trace("Draft chapters removed", category: "creator", metadata: diagnosticFields.merging(["removed_count": .integer(offsets.count), "chapter_count": .integer(draft.chapters.count)]) { _, new in new })
    }
    func moveChapters(from offsets: IndexSet, to index: Int) {
        clearChapterTimes(); draft.chapters.move(fromOffsets: offsets, toOffset: index)
        logger.trace("Draft chapters reordered", category: "creator", metadata: diagnosticFields.merging(["moved_count": .integer(offsets.count), "destination_index": .integer(index)]) { _, new in new })
    }

    func removeFullNarration() {
        draft.audio = nil; draft.audioDuration = nil; clearChapterTimes()
        logger.trace("Draft full book narration removed", category: "creator", metadata: diagnosticFields)
    }

    private func clearChapterTimes() {
        for index in draft.chapters.indices { draft.chapters[index].startTime = nil }
    }

    func setImage(_ data: Data, chapterID: UUID? = nil) async {
        guard !working, !closing else { return }
        var context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "draft_image_decode")
        context.details["byte_count"] = .integer(data.count)
        context.details["chapter_artwork"] = .bool(chapterID != nil)
        if let chapterID { context.details["chapter_id"] = .string(chapterID.uuidString) }
        logger.trace("Draft image update started", category: "creator", metadata: context.metadata)
        working = true
        defer { working = false }
        do {
            guard data.count <= 50_000_000, let cgImage = await ArtworkDecoder.thumbnail(data),
                  let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else {
                throw BookError.invalid("Choose a photo that can be opened on this device.")
            }
            context.phase = "draft_image_save"
            let path = try await store.addImage(jpeg, draftID: draft.id)
            if let chapterID {
                guard let index = draft.chapters.firstIndex(where: { $0.id == chapterID }) else {
                    logger.warning("Draft image target chapter no longer exists", category: "creator", metadata: context.metadata)
                    return
                }
                draft.chapters[index].image = path
            } else { draft.cover = path }
            context.phase = "draft_image_persist"
            try await persist(operationID: context.operationID)
            logger.trace("Draft image update completed", category: "creator", metadata: context.metadata)
        } catch {
            let failureEntry = context.failureEntry("Draft image save failed", error: error, category: "creator")
            await store.flushDiagnosticLogs()
            logger.log(failureEntry)
            message = error.localizedDescription
        }
    }

    func setAudio(_ url: URL, chapterID: UUID) async -> Bool {
        guard !working, !closing else { return false }
        guard draft.audio == nil else {
            logger.trace("Chapter recording blocked by existing full book narration", category: "creator", metadata: diagnosticFields)
            message = String(localized: "Remove the full-book narration before adding chapter recordings.")
            return false
        }
        working = true
        defer { working = false }
        let previous = draft.chapters.first { $0.id == chapterID }
        var context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "chapter_audio_import")
        context.details["chapter_id"] = .string(chapterID.uuidString)
        logger.trace("Chapter recording attachment started", category: "creator", metadata: context.metadata)
        do {
            let audio = try await store.addAudio(url, draftID: draft.id, operationID: context.operationID)
            guard let index = draft.chapters.firstIndex(where: { $0.id == chapterID }) else {
                logger.warning("Chapter recording target no longer exists", category: "creator", metadata: context.metadata)
                return false
            }
            draft.chapters[index].audio = audio.path
            draft.chapters[index].audioDuration = audio.duration
            context.phase = "chapter_audio_persist"
            try await persist(operationID: context.operationID)
            context.details["duration_seconds"] = .double(audio.duration)
            logger.trace("Chapter recording attachment completed", category: "creator", metadata: context.metadata)
            return true
        } catch {
            let failureEntry = context.failureEntry("Chapter recording save failed", error: error, category: "creator")
            await store.flushDiagnosticLogs()
            logger.log(failureEntry)
            if let previous, let index = draft.chapters.firstIndex(where: { $0.id == chapterID }) {
                draft.chapters[index].audio = previous.audio
                draft.chapters[index].audioDuration = previous.audioDuration
            }
            message = String(localized: "The recording could not be added. Your previous narration is still saved. Try again.")
            return false
        }
    }

    func setFullAudio(_ url: URL) async -> Bool {
        guard !working, !closing else { return false }
        working = true
        defer { working = false }
        let previous = draft
        var context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "full_audio_import")
        logger.trace("Full book recording attachment started", category: "creator", metadata: context.metadata)
        do {
            let audio = try await store.addAudio(url, draftID: draft.id, operationID: context.operationID)
            draft.audio = audio.path; draft.audioDuration = audio.duration
            for index in draft.chapters.indices {
                draft.chapters[index].audio = nil; draft.chapters[index].audioDuration = nil; draft.chapters[index].startTime = nil
            }
            context.phase = "full_audio_persist"
            try await persist(operationID: context.operationID)
            context.details["duration_seconds"] = .double(audio.duration)
            logger.trace("Full book recording attachment completed", category: "creator", metadata: context.metadata)
            return true
        } catch {
            let failureEntry = context.failureEntry("Full book recording save failed", error: error, category: "creator")
            await store.flushDiagnosticLogs()
            logger.log(failureEntry)
            draft = previous
            message = String(localized: "The recording could not be added. Your previous narration is still saved. Try again.")
            return false
        }
    }

    /// A generated book becomes one draft change only after every chapter is playable.
    func setGeneratedAudio(_ urls: [UUID: URL], expectedSnapshot: BookDraft,
                           authorized: @MainActor () -> Bool = { true }) async -> Bool {
        guard !working, !closing, authorized(), draft.hasSameContent(as: expectedSnapshot) else {
            logger.trace("Generated narration attachment rejected after editor changed", category: "creator", metadata: diagnosticFields)
            message = String(localized: "This book changed after narration was created. Create a new narration for the current text.")
            return false
        }
        let chapterIDs = Set(draft.chapters.filter { !NarrationSnapshot.paragraphs(in: $0).isEmpty }.map(\.id))
        guard !chapterIDs.isEmpty, Set(urls.keys) == chapterIDs else {
            logger.warning("Generated narration attachment has incomplete chapter outputs", category: "creator", metadata: diagnosticFields.merging(["expected_chapter_count": .integer(chapterIDs.count), "received_chapter_count": .integer(urls.count)]) { _, new in new })
            message = String(localized: "Some chapters are missing. Your saved narration is unchanged.")
            return false
        }
        working = true
        defer { working = false }
        let previous = draft
        let pending = autosave
        pending?.cancel()
        await pending?.value
        var copied: [UUID: (path: String, duration: Double)] = [:]
        var context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "generated_audio_copy")
        context.details["chapter_count"] = .integer(chapterIDs.count)
        logger.trace("Generated narration attachment started", category: "creator", metadata: context.metadata)
        do {
            for chapter in previous.chapters where chapterIDs.contains(chapter.id) {
                try Task.checkCancellation()
                guard authorized(), !closing, draft.hasSameContent(as: previous), let url = urls[chapter.id] else {
                    throw CancellationError()
                }
                context.details["chapter_id"] = .string(chapter.id.uuidString)
                copied[chapter.id] = try await store.addAudio(url, draftID: draft.id, operationID: context.operationID)
            }
            guard authorized(), !closing, draft.hasSameContent(as: previous) else { throw CancellationError() }
            var replacement = previous
            replacement.audio = nil; replacement.audioDuration = nil
            for index in replacement.chapters.indices {
                replacement.chapters[index].audio = copied[replacement.chapters[index].id]?.path
                replacement.chapters[index].audioDuration = copied[replacement.chapters[index].id]?.duration
                replacement.chapters[index].startTime = nil
            }
            replacement.modifiedAt = Date()
            context.phase = "generated_audio_persist"
            try await store.save(replacement, context: context)
            // Disk publication is atomic. An account change during it cannot attach
            // the result to another person's editor.
            guard authorized(), !closing, draft.hasSameContent(as: previous) else {
                var restored = previous; restored.modifiedAt = Date()
                context.phase = "generated_audio_restore_previous"
                try await store.save(restored, context: context)
                throw CancellationError()
            }
            draft = replacement
            autosave?.cancel(); saved = true
            await store.flushDiagnosticLogs()
            logger.trace("Generated narration attachment completed", category: "creator", metadata: context.metadata)
            return true
        } catch {
            let failureEntry = context.failureEntry("Generated narration save failed", error: error, category: "creator")
            await store.removeMedia(copied.values.map(\.path), draftID: previous.id)
            await store.flushDiagnosticLogs()
            if ErrorSnapshot.isCancellation(error) {
                logger.trace("Generated narration save cancelled", category: "creator", metadata: context.metadata)
            } else {
                logger.log(failureEntry)
                message = String(localized: "Narration could not be added. Your previous recordings and text are still saved. Try again.")
            }
            return false
        }
    }

    func save(to library: LibraryModel, asCopy: Bool = false) async -> Bool {
        guard !working, !closing, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        working = true
        defer { working = false }
        conflict = false
        var context = BookOperationDiagnostics(bookID: draft.source?.bookID, draftID: draft.id, phase: "publication_persist")
        context.details["as_copy"] = .bool(asCopy)
        context.details["chapter_count"] = .integer(draft.chapters.count)
        logger.trace("Book save requested", category: "creator", metadata: context.metadata)
        do {
            try await persist(operationID: context.operationID)
            var publication = draft
            if asCopy { publication.source = nil }
            context.phase = "publication_stage"
            let book = try await store.stageBook(publication, operationID: context.operationID)
            await store.flushDiagnosticLogs()
            context.phase = "publication_library_commit"
            do { try await library.saveBook(book, source: publication.source, operationID: context.operationID) }
            catch { await library.repository.discardImport(book); throw error }
            closing = true
            autosave?.cancel()
            do { try await store.remove(draft.id) }
            catch { logger.warning("Published draft cleanup failed", error: error, category: "creator", metadata: context.metadata) }
            await store.flushDiagnosticLogs()
            logger.log(LogEntry("Book saved to library", category: "creator", metadata: context.metadata))
            return true
        } catch is CancellationError {
            await store.flushDiagnosticLogs()
            logger.trace("Book publication cancelled", category: "creator", metadata: context.metadata)
            return false
        } catch {
            let isConflict: Bool
            if case BookError.editConflict = error { isConflict = true } else { isConflict = false }
            let failureEntry = context.failureEntry(isConflict ? "Book editing conflict" : "Book publication failed", error: error, category: "creator", level: isConflict ? .warning : .error)
            await store.flushDiagnosticLogs()
            if isConflict {
                logger.log(failureEntry)
                conflict = true
                return false
            }
            logger.log(failureEntry)
            message = String(localized: "The book could not be saved to your library. Your edits are safe on this device. Check iCloud Drive and available storage, then try again.")
            return false
        }
    }

    isolated deinit { autosave?.cancel() }
}
