import AVFoundation
import Foundation
import MZAppFoundation

actor BookDraftStore {
    @MainActor static let shared = BookDraftStore(root: URL.applicationSupportDirectory.appendingPathComponent("BookDrafts", isDirectory: true), logDestination: FeatureLogDestination(logger: AppLog.logger))
    let root: URL
    private let files = FileManager.default
    private var diagnosticLog: FeatureLogBuffer

    init(root: URL, logDestination: FeatureLogDestination? = nil) {
        self.root = root
        diagnosticLog = FeatureLogBuffer(destination: logDestination)
    }

    func flushDiagnosticLogs() async { await diagnosticLog.flush() }

    func list() throws -> [BookDraft] {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        return try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .compactMap { folder in
                guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }
                return try load(id)
            }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func create() throws -> BookDraft {
        let draft = BookDraft()
        try save(draft)
        return draft
    }

    func createEditingDraft(_ checkout: BookEditCheckout) throws -> BookDraft {
        let book = checkout.book
        var draft = BookDraft()
        draft.source = checkout.source
        draft.title = book.manifest.title; draft.author = book.manifest.author ?? ""
        draft.summary = book.manifest.description ?? ""
        draft.cover = book.manifest.cover; draft.audio = book.manifest.audio
        draft.readingWordsPerMinute = book.manifest.readingWordsPerMinute
        draft.illustrationGuide = book.manifest.illustrationGuide
        draft.chapters = try book.manifest.orderedChapters.map { chapter in
            var value = DraftChapter(id: chapter.id, title: chapter.title ?? "")
            if let path = chapter.text {
                let url = try SafeBookPath.resolve(path, inside: book.folder)
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw BookError.invalid("Chapter text is too large to display.") }
                value.text = try String(contentsOf: url, encoding: .utf8)
            }
            value.image = chapter.image; value.audio = chapter.audio; value.startTime = chapter.startTime
            return value
        }
        do {
            let destination = folder(draft.id)
            try files.createDirectory(at: destination, withIntermediateDirectories: true)
            for path in Set(draft.mediaPaths) {
                let target = try SafeBookPath.resolve(path, inside: destination)
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: SafeBookPath.resolve(path, inside: book.folder), to: target)
            }
            try save(draft)
            try JSONEncoder().encode(draft).write(to: destination.appendingPathComponent("baseline.json"), options: .atomic)
            return draft
        } catch { removeIfPresent(folder(draft.id), phase: "editing_draft"); throw error }
    }

    func baseline(_ id: UUID) throws -> BookDraft? {
        let url = folder(id).appendingPathComponent("baseline.json")
        guard files.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(BookDraft.self, from: Data(contentsOf: url))
    }

    func load(_ id: UUID) throws -> BookDraft {
        let data = try Data(contentsOf: folder(id).appendingPathComponent("draft.json"))
        let draft = try JSONDecoder().decode(BookDraft.self, from: data)
        guard draft.id == id else { throw BookError.invalid("The draft identity has changed.") }
        try draft.validateDraft()
        return draft
    }

    func save(_ draft: BookDraft) throws {
        try Task.checkCancellation()
        try draft.validateDraft()
        let location = folder(draft.id)
        // Ignore a delayed autosave that arrived after a newer explicit save.
        if files.fileExists(atPath: location.appendingPathComponent("draft.json").path) {
            do { if try load(draft.id).modifiedAt > draft.modifiedAt { return } }
            catch { diagnosticLog.warning("Existing draft validation failed before save", error: error, category: "creator") }
        }
        try files.createDirectory(at: location, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(draft).write(to: location.appendingPathComponent("draft.json"), options: .atomic)
    }

    func remove(_ id: UUID) throws { try files.removeItem(at: folder(id)) }

    func mediaURL(_ path: String, draftID: UUID) throws -> URL {
        try SafeBookPath.resolve(path, inside: folder(draftID))
    }

    func addImage(_ jpeg: Data, draftID: UUID) throws -> String {
        guard !jpeg.isEmpty, jpeg.count <= 30_000_000 else { throw BookError.invalid("Image is too large to display.") }
        let path = "images/\(UUID().uuidString).jpg"
        let url = try mediaURL(path, draftID: draftID)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url, options: .atomic)
        return path
    }

    func imageData(at url: URL) throws -> Data {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 30_000_000 else {
            throw BookError.invalid("Image is too large to display.")
        }
        return try Data(contentsOf: url)
    }

    func addAudio(_ source: URL, draftID: UUID) async throws -> (path: String, duration: Double) {
        let ext = source.pathExtension.lowercased()
        guard ["m4a", "mp3", "wav"].contains(ext) else { throw BookError.invalid("Choose an M4A, MP3, or WAV recording.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let path = "audio/\(UUID().uuidString).\(ext)"
        let destination = try mediaURL(path, draftID: draftID)
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var copyResult: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            copyResult = Result {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= 512_000_000 else {
                    throw BookError.invalid("This recording is too large. Choose a file under 512 MB.")
                }
                try files.copyItem(at: url, to: destination)
            }
        }
        do {
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw BookError.unavailable("The recording is not available. Download it in Files and try again.") }
            try copyResult.get()
            let duration = try await AVURLAsset(url: destination).load(.duration).seconds
            try Task.checkCancellation()
            guard duration.isFinite, duration > 0 else { throw BookError.invalid("This recording has no playable audio.") }
            let tracks = try await AVURLAsset(url: destination).loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else { throw BookError.invalid("This recording has no playable audio.") }
            return (path, duration)
        } catch { removeIfPresent(destination, phase: "failed_audio_copy"); throw error }
    }

    func removeMedia(_ paths: [String], draftID: UUID) {
        for path in paths {
            do { removeIfPresent(try mediaURL(path, draftID: draftID), phase: "draft_media") }
            catch { diagnosticLog.warning("Draft media cleanup resolution failed", error: error, category: "creator") }
        }
    }

    func stageBook(_ draft: BookDraft) throws -> LibraryBook {
        try draft.validateDraft()
        let manifest = draft.manifest
        try manifest.validate()
        let workspace = files.temporaryDirectory.appendingPathComponent("BedtimeCreated-\(UUID().uuidString)", isDirectory: true)
        let output = workspace.appendingPathComponent("Book", isDirectory: true)
        do {
            try files.createDirectory(at: output, withIntermediateDirectories: true)
            for chapter in draft.chapters where !chapter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let url = output.appendingPathComponent("text/\(chapter.id.uuidString).md")
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(chapter.text.utf8).write(to: url, options: .atomic)
            }
            for path in Set(draft.mediaPaths) {
                try Task.checkCancellation()
                let source = try mediaURL(path, draftID: draft.id)
                let destination = try SafeBookPath.resolve(path, inside: output)
                try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: source, to: destination)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: output.appendingPathComponent("book.json"), options: .atomic)
            _ = try BookManifest.load(from: output, requireAssets: true)
            return LibraryBook(manifest: manifest, folder: output)
        } catch { removeIfPresent(workspace, phase: "publication_workspace"); throw error }
    }

    private func removeIfPresent(_ url: URL, phase: String) {
        guard files.fileExists(atPath: url.path) else { return }
        do { try files.removeItem(at: url) }
        catch { diagnosticLog.warning("Draft cleanup failed", error: error, category: "creator", metadata: ["phase": .string(phase)]) }
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
}
