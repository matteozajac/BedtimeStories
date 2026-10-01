import Foundation
import Observation
import SwiftUI
import UIKit

@Observable @MainActor
final class BookEditorModel {
    var draft: BookDraft {
        didSet {
            if oldValue.title != draft.title || oldValue.author != draft.author || oldValue.summary != draft.summary || oldValue.cover != draft.cover || oldValue.chapters != draft.chapters {
                changed()
            }
        }
    }
    var message: String?
    private(set) var working = false
    private(set) var saved = true
    let store: BookDraftStore
    @ObservationIgnored private var autosave: Task<Void, Never>?
    @ObservationIgnored private var closing = false

    init(draft: BookDraft, store: BookDraftStore) { self.draft = draft; self.store = store }

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
        autosave?.cancel()
        saved = false
        draft.modifiedAt = Date()
        let snapshot = draft
        try await store.save(snapshot)
        if draft == snapshot { saved = true }
    }

    func close() async -> Bool {
        guard !working else { return false }
        working = true
        defer { working = false }
        closing = true
        do { try await persist(); return true }
        catch { closing = false; message = String(localized: "Your draft could not be saved. Keep the editor open and try again."); return false }
    }

    func addChapter() { draft.chapters.append(DraftChapter()) }
    func deleteChapters(at offsets: IndexSet) { draft.chapters.remove(atOffsets: offsets) }
    func moveChapters(from offsets: IndexSet, to index: Int) { draft.chapters.move(fromOffsets: offsets, toOffset: index) }

    func setImage(_ data: Data, chapterID: UUID? = nil) async {
        guard !working else { return }
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
        guard !working else { return false }
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

    func publish(to library: LibraryModel) async {
        guard !working, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true
        defer { working = false }
        do {
            try await persist()
            let book = try await store.stageBook(draft)
            do { try await library.addCreatedBook(book) }
            catch { await library.repository.discardImport(book); throw error }
            closing = true
            autosave?.cancel()
            try? await store.remove(draft.id)
            library.showingCreator = false
        } catch { message = String(localized: "The book could not be added to your library. Your draft is safe. Check the folder in Files, then try again.") }
    }

    isolated deinit { autosave?.cancel() }
}
