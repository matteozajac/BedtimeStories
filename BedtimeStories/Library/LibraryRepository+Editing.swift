import CryptoKit
import Foundation
import MZAppFoundation

extension LibraryRepository {
    func checkout(_ book: LibraryBook, root: URL, operationID: String = UUID().uuidString) async throws -> BookEditCheckout {
        let files = FileManager.default
        var context = BookOperationDiagnostics(operationID: operationID, bookID: book.id, phase: "checkout_validate_source")
        context.details["chapter_count"] = .integer(book.manifest.orderedChapters.count)
        diagnosticLog.trace("Book edit checkout started", category: "library", metadata: context.metadata)
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        var workspace: URL?
        do {
            guard book.folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw BookError.editConflict }
            context.phase = "checkout_manifest_download"
            let manifestURL = try SafeBookPath.resolve("book.json", inside: book.folder)
            try await download(manifestURL, context: context)
            context.phase = "checkout_manifest_read"
            let current = try coordinatedRead(book.folder, context: context) { try BookManifest.load(from: $0) }
            guard current.id == book.id else { throw BookError.editConflict }
            let paths = Set(current.assetPaths).sorted()
            context.details["asset_count"] = .integer(paths.count)
            diagnosticLog.trace("Book edit manifest opened", category: "library", metadata: context.metadata)
            context.phase = "checkout_asset_download"
            for (index, path) in paths.enumerated() {
                try Task.checkCancellation()
                context.details["asset_index"] = .integer(index + 1)
                context.identifyAsset(path, manifest: current)
                diagnosticLog.trace("Book edit asset preparation started", category: "library", metadata: context.metadata)
                try await download(try SafeBookPath.resolve(path, inside: book.folder), context: context)
                diagnosticLog.trace("Book edit asset preparation completed", category: "library", metadata: context.metadata)
            }
            context.details.removeValue(forKey: "asset_index")
            context.details.removeValue(forKey: "asset_kind")
            let location = files.temporaryDirectory.appendingPathComponent("BedtimeEdit-\(UUID().uuidString)")
            workspace = location
            let copy = location.appendingPathComponent("Book")
            context.phase = "checkout_workspace_create"
            try files.createDirectory(at: location, withIntermediateDirectories: true)
            context.phase = "checkout_copy_and_fingerprint"
            let result = try coordinatedRead(book.folder, context: context) { folder in
                let manifest = try BookManifest.load(from: folder, requireAssets: true)
                guard manifest.id == book.id else { throw BookError.editConflict }
                diagnosticLog.trace("Book edit source fingerprint started", category: "library", metadata: context.metadata)
                let hash = try Self.editFingerprint(folder)
                diagnosticLog.trace("Book edit source fingerprint completed", category: "library", metadata: context.metadata)
                try files.createDirectory(at: copy, withIntermediateDirectories: true)
                for (index, path) in Set(["book.json"] + manifest.assetPaths).sorted().enumerated() {
                    try Task.checkCancellation()
                    context.details["asset_index"] = .integer(index + 1)
                    context.identifyAsset(path, manifest: manifest)
                    let destination = try SafeBookPath.resolve(path, inside: copy)
                    try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    diagnosticLog.trace("Book edit asset copy started", category: "library", metadata: context.metadata)
                    try files.copyItem(at: SafeBookPath.resolve(path, inside: folder), to: destination)
                    diagnosticLog.trace("Book edit asset copy completed", category: "library", metadata: context.metadata)
                }
                context.phase = "checkout_copy_verify"
                diagnosticLog.trace("Book edit copy verification started", category: "library", metadata: context.metadata)
                guard try Self.editFingerprint(copy) == hash else { throw BookError.editConflict }
                return BookEditCheckout(book: LibraryBook(manifest: manifest, folder: copy), source: BookEditSource(bookID: book.id, libraryRoot: root, fingerprint: hash))
            }
            context.phase = "checkout_complete"
            context.details.removeValue(forKey: "asset_index")
            context.details.removeValue(forKey: "asset_kind")
            diagnosticLog.trace("Book edit checkout completed", category: "library", metadata: context.metadata)
            return result
        } catch {
            diagnosticLog.trace("Book edit checkout interrupted", category: "library", metadata: context.metadata)
            if let workspace { removeIfPresent(workspace, operation: "editing_workspace") }
            throw BookOperationFailure.preserving(error, context: context)
        }
    }

    func commitEdit(_ staged: LibraryBook, source: BookEditSource, root: URL, operationID: String = UUID().uuidString) throws {
        var context = BookOperationDiagnostics(operationID: operationID, bookID: source.bookID, phase: "commit_edit_validate")
        context.details["chapter_count"] = .integer(staged.manifest.orderedChapters.count)
        diagnosticLog.trace("Book edit publication started", category: "library", metadata: context.metadata)
        do {
            let files = FileManager.default
            guard source.libraryRoot.standardizedFileURL == root.standardizedFileURL, staged.id == source.bookID else { throw BookError.editConflict }
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            context.phase = "commit_edit_find_original"
            let matches = try coordinatedRead(root, context: context) { folder in
                let candidates = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                return candidates.enumerated().compactMap { index, candidate -> URL? in
                    do { return try BookManifest.load(from: candidate).id == source.bookID ? candidate : nil }
                    catch {
                        // Ordinary non-book folders have no manifest and are expected.
                        let manifest = candidate.appendingPathComponent("book.json")
                        let placeholder = candidate.appendingPathComponent(".book.json.icloud")
                        guard FileManager.default.fileExists(atPath: manifest.path) || FileManager.default.fileExists(atPath: placeholder.path) else { return nil }
                        var fields = context.metadata; fields["folder_index"] = .integer(index + 1)
                        diagnosticLog.warning("Book edit destination manifest unavailable; excluding candidate", error: error, category: "library", metadata: fields)
                        return nil
                    }
                }
            }
            guard matches.count == 1, let destination = matches.first else { throw BookError.editConflict }
            let cache = cacheRoot.appendingPathComponent(source.bookID.uuidString)
            let pinned = files.fileExists(atPath: cache.appendingPathComponent(".pinned").path)
            context.details["offline_pinned"] = .bool(pinned)
            let preparedCache = cacheRoot.appendingPathComponent(".incoming-\(UUID().uuidString)")
            let previousCache = cacheRoot.appendingPathComponent(".backup-\(UUID().uuidString)")
            defer { removeIfPresent(preparedCache, operation: "prepared_edit_cache") }
            // Prepare a complete offline copy before changing the library. Storage failure leaves both originals intact.
            if pinned {
                context.phase = "commit_edit_prepare_offline_copy"
                diagnosticLog.trace("Book edit offline copy preparation started", category: "library", metadata: context.metadata)
                try files.copyItem(at: staged.folder, to: preparedCache)
                try Data().write(to: preparedCache.appendingPathComponent(".pinned"))
            }
            var coordinationError: NSError?
            var result: Result<Void, Error>?
            context.phase = "commit_edit_provider_coordination"
            diagnosticLog.trace("Book edit file provider write coordination requested", category: "library", metadata: context.metadata)
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { folder in
                result = Result {
                    diagnosticLog.trace("Book edit file provider write access granted", category: "library", metadata: context.metadata)
                    context.phase = "commit_edit_verify_original"
                    guard try Self.editFingerprint(folder) == source.fingerprint else { throw BookError.editConflict }
                    let incoming = root.appendingPathComponent(".incoming-\(UUID().uuidString)")
                    let backup = root.appendingPathComponent(".backup-\(UUID().uuidString)")
                    defer { removeIfPresent(incoming, operation: "editing_incoming") }
                    try Task.checkCancellation()
                    context.phase = "commit_edit_copy_replacement"
                    diagnosticLog.trace("Book edit replacement copy started", category: "library", metadata: context.metadata)
                    try files.copyItem(at: staged.folder, to: incoming)
                    _ = try BookManifest.load(from: incoming, requireAssets: true)
                    try Task.checkCancellation()
                    guard try Self.editFingerprint(folder) == source.fingerprint else { throw BookError.editConflict }
                    context.phase = "commit_edit_replace_original"
                    diagnosticLog.trace("Book edit replacement started", category: "library", metadata: context.metadata)
                    try files.moveItem(at: folder, to: backup)
                    do {
                        try files.moveItem(at: incoming, to: folder)
                        if pinned {
                            context.phase = "commit_edit_replace_offline_copy"
                            try files.moveItem(at: cache, to: previousCache)
                            do { try files.moveItem(at: preparedCache, to: cache) }
                            catch { try files.moveItem(at: previousCache, to: cache); throw error }
                        }
                    } catch {
                        diagnosticLog.trace("Book edit original restoration started", category: "library", metadata: context.metadata)
                        removeIfPresent(folder, operation: "failed_edit_destination")
                        try files.moveItem(at: backup, to: folder)
                        throw error
                    }
                    removeIfPresent(backup, operation: "editing_backup")
                    if pinned { removeIfPresent(previousCache, operation: "previous_edit_cache") }
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw BookError.unavailable(String(localized: "The book could not be opened for saving.")) }
            try result.get()
            discardImport(staged)
            if !pinned { removeIfPresent(cache, operation: "unrequested_edit_cache") }
            context.phase = "commit_edit_complete"
            diagnosticLog.trace("Book edit publication completed", category: "library", metadata: context.metadata)
        } catch {
            diagnosticLog.trace("Book edit publication interrupted", category: "library", metadata: context.metadata)
            throw BookOperationFailure.preserving(error, context: context)
        }
    }

    private static func editFingerprint(_ folder: URL) throws -> String {
        guard NSFileVersion.unresolvedConflictVersionsOfItem(at: folder)?.isEmpty != false else { throw BookError.editConflict }
        let manifest = try BookManifest.load(from: folder, requireAssets: true)
        var hash = SHA256()
        for path in Set(["book.json"] + manifest.assetPaths).sorted() {
            try Task.checkCancellation()
            let url = try SafeBookPath.resolve(path, inside: folder)
            guard NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.isEmpty != false else { throw BookError.editConflict }
            hash.update(data: Data(path.utf8)); hash.update(data: Data([0]))
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            hash.update(data: Data([0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
