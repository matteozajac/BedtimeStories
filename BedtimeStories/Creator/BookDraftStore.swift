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

    func createEditingDraft(_ checkout: BookEditCheckout, operationID: String = UUID().uuidString) throws -> BookDraft {
        let book = checkout.book
        var draft = BookDraft()
        draft.source = checkout.source
        var context = BookOperationDiagnostics(operationID: operationID, bookID: checkout.source.bookID, draftID: draft.id, phase: "editing_draft_read_text")
        context.details["chapter_count"] = .integer(book.manifest.orderedChapters.count)
        diagnosticLog.trace("Editing draft creation started", category: "creator", metadata: context.metadata)
        draft.title = book.manifest.title; draft.author = book.manifest.author ?? ""
        draft.summary = book.manifest.description ?? ""
        draft.cover = book.manifest.cover; draft.audio = book.manifest.audio
        draft.readingWordsPerMinute = book.manifest.readingWordsPerMinute
        draft.illustrationGuide = book.manifest.illustrationGuide
        do {
            draft.chapters = try book.manifest.orderedChapters.enumerated().map { index, chapter in
                context.details["chapter_id"] = .string(chapter.id.uuidString)
                context.details["chapter_index"] = .integer(index + 1)
                var value = DraftChapter(id: chapter.id, title: chapter.title ?? "")
                if let path = chapter.text {
                    let url = try SafeBookPath.resolve(path, inside: book.folder)
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw BookError.invalid("Chapter text is too large to display.") }
                    diagnosticLog.trace("Editing draft chapter text read started", category: "creator", metadata: context.metadata)
                    value.text = try String(contentsOf: url, encoding: .utf8)
                    diagnosticLog.trace("Editing draft chapter text read completed", category: "creator", metadata: context.metadata)
                }
                value.image = chapter.image; value.audio = chapter.audio; value.startTime = chapter.startTime
                return value
            }
            context.details.removeValue(forKey: "chapter_id")
            context.details.removeValue(forKey: "chapter_index")
            context.phase = "editing_draft_copy_media"
            context.details["asset_count"] = .integer(Set(draft.mediaPaths).count)
            let destination = folder(draft.id)
            try files.createDirectory(at: destination, withIntermediateDirectories: true)
            for (index, path) in Set(draft.mediaPaths).sorted().enumerated() {
                try Task.checkCancellation()
                context.details["asset_index"] = .integer(index + 1)
                context.details["asset_kind"] = .string(BookOperationDiagnostics.assetKind(path))
                diagnosticLog.trace("Editing draft media copy started", category: "creator", metadata: context.metadata)
                let target = try SafeBookPath.resolve(path, inside: destination)
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: SafeBookPath.resolve(path, inside: book.folder), to: target)
                diagnosticLog.trace("Editing draft media copy completed", category: "creator", metadata: context.metadata)
            }
            context.details.removeValue(forKey: "asset_index")
            context.details.removeValue(forKey: "asset_kind")
            context.phase = "editing_draft_save"
            try save(draft, context: context)
            context.phase = "editing_draft_baseline_write"
            diagnosticLog.trace("Editing draft baseline write started", category: "creator", metadata: context.metadata)
            try JSONEncoder().encode(draft).write(to: destination.appendingPathComponent("baseline.json"), options: .atomic)
            diagnosticLog.trace("Editing draft creation completed", category: "creator", metadata: context.metadata)
            return draft
        } catch { removeIfPresent(folder(draft.id), phase: "editing_draft"); throw BookOperationFailure.preserving(error, context: context) }
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

    func save(_ draft: BookDraft, context: BookOperationDiagnostics? = nil) throws {
        if let context { diagnosticLog.trace("Draft disk save validation started", category: "creator", metadata: context.metadata) }
        try Task.checkCancellation()
        try draft.validateDraft()
        let location = folder(draft.id)
        // Ignore a delayed autosave that arrived after a newer explicit save.
        if files.fileExists(atPath: location.appendingPathComponent("draft.json").path) {
            do { if try load(draft.id).modifiedAt > draft.modifiedAt {
                if let context { diagnosticLog.trace("Draft disk save skipped older snapshot", category: "creator", metadata: context.metadata) }
                return
            } }
            catch { diagnosticLog.warning("Existing draft validation failed before save", error: error, category: "creator", metadata: ["draft_id": .string(draft.id.uuidString), "phase": .string("validate_existing_draft")]) }
        }
        try files.createDirectory(at: location, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let context { diagnosticLog.trace("Draft disk atomic write started", category: "creator", metadata: context.metadata) }
        try encoder.encode(draft).write(to: location.appendingPathComponent("draft.json"), options: .atomic)
        if let context { diagnosticLog.trace("Draft disk atomic write completed", category: "creator", metadata: context.metadata) }
    }

    func remove(_ id: UUID) throws {
        let context = BookOperationDiagnostics(draftID: id, phase: "draft_remove")
        diagnosticLog.trace("Draft disk deletion started", category: "creator", metadata: context.metadata)
        try files.removeItem(at: folder(id))
        diagnosticLog.trace("Draft disk deletion completed", category: "creator", metadata: context.metadata)
    }

    func mediaURL(_ path: String, draftID: UUID) throws -> URL {
        try SafeBookPath.resolve(path, inside: folder(draftID))
    }

    func addImage(_ jpeg: Data, draftID: UUID) throws -> String {
        var context = BookOperationDiagnostics(draftID: draftID, phase: "draft_image_write")
        context.details["byte_count"] = .integer(jpeg.count)
        diagnosticLog.trace("Draft image disk write started", category: "creator", metadata: context.metadata)
        guard !jpeg.isEmpty, jpeg.count <= 30_000_000 else { throw BookError.invalid("Image is too large to display.") }
        let path = "images/\(UUID().uuidString).jpg"
        let url = try mediaURL(path, draftID: draftID)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url, options: .atomic)
        diagnosticLog.trace("Draft image disk write completed", category: "creator", metadata: context.metadata)
        return path
    }

    func imageData(at url: URL) throws -> Data {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 30_000_000 else {
            throw BookError.invalid("Image is too large to display.")
        }
        return try Data(contentsOf: url)
    }

    func addAudio(_ source: URL, draftID: UUID, operationID: String = UUID().uuidString) async throws -> (path: String, duration: Double) {
        var context = BookOperationDiagnostics(operationID: operationID, draftID: draftID, phase: "draft_audio_validate_type")
        diagnosticLog.trace("Draft audio import started", category: "creator", metadata: context.metadata)
        let ext = source.pathExtension.lowercased()
        guard ["m4a", "mp3", "wav"].contains(ext) else { throw BookError.invalid("Choose an M4A, MP3, or WAV recording.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let path = "audio/\(UUID().uuidString).\(ext)"
        let destination = try mediaURL(path, draftID: draftID)
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var copyResult: Result<Void, Error>?
        context.phase = "draft_audio_provider_coordination"
        diagnosticLog.trace("Draft audio file provider read coordination requested", category: "creator", metadata: context.metadata)
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            copyResult = Result {
                diagnosticLog.trace("Draft audio file provider read access granted", category: "creator", metadata: context.metadata)
                context.phase = "draft_audio_copy"
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= 512_000_000 else {
                    throw BookError.invalid("This recording is too large. Choose a file under 512 MB.")
                }
                context.details["byte_count"] = .integer(values.fileSize ?? 0)
                diagnosticLog.trace("Draft audio disk copy started", category: "creator", metadata: context.metadata)
                try files.copyItem(at: url, to: destination)
                diagnosticLog.trace("Draft audio disk copy completed", category: "creator", metadata: context.metadata)
            }
        }
        do {
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw BookError.unavailable("The recording is not available. Download it in Files and try again.") }
            try copyResult.get()
            context.phase = "draft_audio_duration_validate"
            diagnosticLog.trace("Draft audio duration validation started", category: "creator", metadata: context.metadata)
            let duration = try await AVURLAsset(url: destination).load(.duration).seconds
            try Task.checkCancellation()
            guard duration.isFinite, duration > 0 else { throw BookError.invalid("This recording has no playable audio.") }
            context.phase = "draft_audio_tracks_validate"
            let tracks = try await AVURLAsset(url: destination).loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else { throw BookError.invalid("This recording has no playable audio.") }
            context.details["duration_seconds"] = .double(duration)
            context.details["audio_track_count"] = .integer(tracks.count)
            diagnosticLog.trace("Draft audio import completed", category: "creator", metadata: context.metadata)
            return (path, duration)
        } catch { removeIfPresent(destination, phase: "failed_audio_copy"); throw BookOperationFailure.preserving(error, context: context) }
    }

    func removeMedia(_ paths: [String], draftID: UUID) {
        for path in paths {
            do { removeIfPresent(try mediaURL(path, draftID: draftID), phase: "draft_media") }
            catch { diagnosticLog.warning("Draft media cleanup resolution failed", error: error, category: "creator", metadata: ["draft_id": .string(draftID.uuidString)]) }
        }
    }

    func stageBook(_ draft: BookDraft, operationID: String = UUID().uuidString) throws -> LibraryBook {
        var context = BookOperationDiagnostics(operationID: operationID, bookID: draft.source?.bookID, draftID: draft.id, phase: "publication_validate")
        context.details["chapter_count"] = .integer(draft.chapters.count)
        context.details["asset_count"] = .integer(Set(draft.mediaPaths).count)
        diagnosticLog.trace("Book publication staging started", category: "creator", metadata: context.metadata)
        try draft.validateDraft()
        let manifest = draft.manifest
        try manifest.validate()
        let workspace = files.temporaryDirectory.appendingPathComponent("BedtimeCreated-\(UUID().uuidString)", isDirectory: true)
        let output = workspace.appendingPathComponent("Book", isDirectory: true)
        do {
            context.phase = "publication_write_text"
            try files.createDirectory(at: output, withIntermediateDirectories: true)
            diagnosticLog.trace("Book publication chapter text write started", category: "creator", metadata: context.metadata)
            for chapter in draft.chapters where !chapter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let url = output.appendingPathComponent("text/\(chapter.id.uuidString).md")
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(chapter.text.utf8).write(to: url, options: .atomic)
            }
            context.phase = "publication_copy_media"
            for (index, path) in Set(draft.mediaPaths).sorted().enumerated() {
                try Task.checkCancellation()
                context.details["asset_index"] = .integer(index + 1)
                context.details["asset_kind"] = .string(BookOperationDiagnostics.assetKind(path))
                diagnosticLog.trace("Book publication media copy started", category: "creator", metadata: context.metadata)
                let source = try mediaURL(path, draftID: draft.id)
                let destination = try SafeBookPath.resolve(path, inside: output)
                try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: source, to: destination)
                diagnosticLog.trace("Book publication media copy completed", category: "creator", metadata: context.metadata)
            }
            context.phase = "publication_manifest_write"
            context.details.removeValue(forKey: "asset_index")
            context.details.removeValue(forKey: "asset_kind")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: output.appendingPathComponent("book.json"), options: .atomic)
            context.phase = "publication_verify_assets"
            diagnosticLog.trace("Book publication staged asset verification started", category: "creator", metadata: context.metadata)
            _ = try BookManifest.load(from: output, requireAssets: true)
            diagnosticLog.trace("Book publication staging completed", category: "creator", metadata: context.metadata)
            return LibraryBook(manifest: manifest, folder: output)
        } catch { removeIfPresent(workspace, phase: "publication_workspace"); throw BookOperationFailure.preserving(error, context: context) }
    }

    private func removeIfPresent(_ url: URL, phase: String) {
        guard files.fileExists(atPath: url.path) else { return }
        do { try files.removeItem(at: url) }
        catch { diagnosticLog.warning("Draft cleanup failed", error: error, category: "creator", metadata: ["phase": .string(phase)]) }
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
}
