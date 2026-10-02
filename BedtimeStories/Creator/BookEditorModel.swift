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

    func loadBaseline() async {
        guard isEditingBook else { return }
        do {
            if let original = try await store.baseline(draft.id) { baseline = original }
            else { baselineAvailable = false }
        } catch {
            logger.error("Editing baseline load failed", error: error, category: "creator")
            baselineAvailable = false; message = String(localized: "The original editing copy could not be opened. Your library book is unchanged.")
        }
    }

    func changed() {
        guard !closing else { return }
        draft.modifiedAt = Date()
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
                self?.logger.error("Draft autosave failed", error: error, category: "creator")
                self?.message = String(localized: "Your draft could not be saved. Keep the editor open and try again.")
            }
        }
    }

    func persist() async throws {
        guard !closing else { return }
        let pending = autosave
        pending?.cancel()
        await pending?.value
        saved = false
        draft.modifiedAt = Date()
        let snapshot = draft
        try await store.save(snapshot)
        if draft == snapshot { saved = true }
    }

    func discardAndClose() async -> Bool {
        guard !working else { return false }
        working = true
        defer { working = false }
        closing = true
        autosave?.cancel()
        await autosave?.value
        do {
            if isEditingBook || baseline.isEmpty { try await store.remove(draft.id) }
            else {
                var original = baseline; original.modifiedAt = Date()
                try await store.save(original)
            }
            return true
        }
        catch {
            logger.error("Draft discard failed", error: error, category: "creator")
            closing = false; message = String(localized: "Your draft could not be saved. Keep the editor open and try again."); return false
        }
    }

    func addChapter() { clearChapterTimes(); draft.chapters.append(DraftChapter()) }
    func deleteChapters(at offsets: IndexSet) { clearChapterTimes(); draft.chapters.remove(atOffsets: offsets) }
    func moveChapters(from offsets: IndexSet, to index: Int) { clearChapterTimes(); draft.chapters.move(fromOffsets: offsets, toOffset: index) }

    func removeFullNarration() { draft.audio = nil; draft.audioDuration = nil; clearChapterTimes() }

    private func clearChapterTimes() {
        for index in draft.chapters.indices { draft.chapters[index].startTime = nil }
    }

    func setImage(_ data: Data, chapterID: UUID? = nil) async {
        guard !working, !closing else { return }
        working = true
        defer { working = false }
        do {
            guard data.count <= 50_000_000, let cgImage = await ArtworkDecoder.thumbnail(data),
                  let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else {
                throw BookError.invalid("Choose a photo that can be opened on this device.")
            }
            let path = try await store.addImage(jpeg, draftID: draft.id)
            if let chapterID {
                guard let index = draft.chapters.firstIndex(where: { $0.id == chapterID }) else { return }
                draft.chapters[index].image = path
            } else { draft.cover = path }
            try await persist()
        } catch {
            logger.error("Draft image save failed", error: error, category: "creator")
            message = error.localizedDescription
        }
    }

    func setAudio(_ url: URL, chapterID: UUID) async -> Bool {
        guard !working, !closing else { return false }
        guard draft.audio == nil else {
            message = String(localized: "Remove the full-book narration before adding chapter recordings.")
            return false
        }
        working = true
        defer { working = false }
        let previous = draft.chapters.first { $0.id == chapterID }
        do {
            let audio = try await store.addAudio(url, draftID: draft.id)
            guard let index = draft.chapters.firstIndex(where: { $0.id == chapterID }) else { return false }
            draft.chapters[index].audio = audio.path
            draft.chapters[index].audioDuration = audio.duration
            try await persist()
            return true
        } catch {
            logger.error("Chapter recording save failed", error: error, category: "creator")
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
        do {
            let audio = try await store.addAudio(url, draftID: draft.id)
            draft.audio = audio.path; draft.audioDuration = audio.duration
            for index in draft.chapters.indices {
                draft.chapters[index].audio = nil; draft.chapters[index].audioDuration = nil; draft.chapters[index].startTime = nil
            }
            try await persist()
            return true
        } catch {
            logger.error("Full book recording save failed", error: error, category: "creator")
            draft = previous
            message = String(localized: "The recording could not be added. Your previous narration is still saved. Try again.")
            return false
        }
    }

    /// A generated book becomes one draft change only after every chapter is playable.
    func setGeneratedAudio(_ urls: [UUID: URL], expectedSnapshot: BookDraft,
                           authorized: @MainActor () -> Bool = { true }) async -> Bool {
        guard !working, !closing, authorized(), draft.hasSameContent(as: expectedSnapshot) else {
            message = String(localized: "This book changed after narration was created. Create a new narration for the current text.")
            return false
        }
        let chapterIDs = Set(draft.chapters.filter { !NarrationSnapshot.paragraphs(in: $0).isEmpty }.map(\.id))
        guard !chapterIDs.isEmpty, Set(urls.keys) == chapterIDs else {
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
        do {
            for chapter in previous.chapters where chapterIDs.contains(chapter.id) {
                try Task.checkCancellation()
                guard authorized(), !closing, draft.hasSameContent(as: previous), let url = urls[chapter.id] else {
                    throw CancellationError()
                }
                copied[chapter.id] = try await store.addAudio(url, draftID: draft.id)
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
            try await store.save(replacement)
            // Disk publication is atomic. An account change during it cannot attach
            // the result to another person's editor.
            guard authorized(), !closing, draft.hasSameContent(as: previous) else {
                var restored = previous; restored.modifiedAt = Date()
                try await store.save(restored)
                throw CancellationError()
            }
            draft = replacement
            autosave?.cancel(); saved = true
            return true
        } catch {
            await store.removeMedia(copied.values.map(\.path), draftID: previous.id)
            if !(error is CancellationError) {
                logger.error("Generated narration save failed", error: error, category: "creator")
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
        do {
            try await persist()
            var publication = draft
            if asCopy { publication.source = nil }
            let book = try await store.stageBook(publication)
            do { try await library.saveBook(book, source: publication.source) }
            catch { await library.repository.discardImport(book); throw error }
            closing = true
            autosave?.cancel()
            try? await store.remove(draft.id)
            logger.log(LogEntry("Book saved to library", category: "creator", metadata: ["as_copy": .bool(asCopy)]))
            return true
        } catch BookError.editConflict {
            logger.log(LogEntry("Book editing conflict", level: .warning, category: "creator"))
            conflict = true
            return false
        } catch {
            logger.error("Book publication failed", error: error, category: "creator")
            message = String(localized: "The book could not be saved to your library. Your edits are safe on this device. Check iCloud Drive and available storage, then try again.")
            return false
        }
    }

    isolated deinit { autosave?.cancel() }
}
