import AVFoundation
import Foundation

actor BookDraftStore {
    static let shared = BookDraftStore(root: URL.applicationSupportDirectory.appendingPathComponent("BookDrafts", isDirectory: true))
    let root: URL
    private let files = FileManager.default

    init(root: URL) { self.root = root }

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

    func load(_ id: UUID) throws -> BookDraft {
        let data = try Data(contentsOf: folder(id).appendingPathComponent("draft.json"))
        let draft = try JSONDecoder().decode(BookDraft.self, from: data)
        guard draft.id == id else { throw BookError.invalid("The draft identity has changed.") }
        try draft.validateDraft()
        return draft
    }

    func save(_ draft: BookDraft) throws {
        try draft.validateDraft()
        let location = folder(draft.id)
        // Ignore a delayed autosave that arrived after a newer explicit save.
        if let existing = try? load(draft.id), existing.modifiedAt > draft.modifiedAt { return }
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
        } catch { try? files.removeItem(at: destination); throw error }
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
        } catch { try? files.removeItem(at: workspace); throw error }
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
}
