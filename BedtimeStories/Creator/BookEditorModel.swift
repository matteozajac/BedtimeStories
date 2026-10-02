import Foundation
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

    init(draft: BookDraft, store: BookDraftStore) { self.draft = draft; baseline = draft; self.store = store }

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
        } catch { baselineAvailable = false; message = String(localized: "The original editing copy could not be opened. Your library book is unchanged.") }
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
            catch { self?.message = String(localized: "Your draft could not be saved. Keep the editor open and try again.") }
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
        catch { closing = false; message = String(localized: "Your draft could not be saved. Keep the editor open and try again."); return false }
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
        } catch { message = error.localizedDescription }
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
            draft = previous
            message = String(localized: "The recording could not be added. Your previous narration is still saved. Try again.")
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
            return true
        } catch BookError.editConflict {
            conflict = true
            return false
        } catch {
            message = String(localized: "The book could not be saved to your library. Your edits are safe on this device. Check iCloud Drive and available storage, then try again.")
            return false
        }
    }

    isolated deinit { autosave?.cancel() }
}
