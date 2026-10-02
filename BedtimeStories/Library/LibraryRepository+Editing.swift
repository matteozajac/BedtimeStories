import CryptoKit
import Foundation

extension LibraryRepository {
    func checkout(_ book: LibraryBook, root: URL) async throws -> BookEditCheckout {
        let files = FileManager.default
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        guard book.folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw BookError.editConflict }
        let manifestURL = try SafeBookPath.resolve("book.json", inside: book.folder)
        try await download(manifestURL)
        let current = try coordinatedRead(book.folder) { try BookManifest.load(from: $0) }
        guard current.id == book.id else { throw BookError.editConflict }
        for path in Set(current.assetPaths) {
            try await download(try SafeBookPath.resolve(path, inside: book.folder))
        }
        let workspace = files.temporaryDirectory.appendingPathComponent("BedtimeEdit-\(UUID().uuidString)")
        let copy = workspace.appendingPathComponent("Book")
        do {
            try files.createDirectory(at: workspace, withIntermediateDirectories: true)
            let result = try coordinatedRead(book.folder) { folder in
                let manifest = try BookManifest.load(from: folder, requireAssets: true)
                guard manifest.id == book.id else { throw BookError.editConflict }
                let hash = try Self.editFingerprint(folder)
                try files.createDirectory(at: copy, withIntermediateDirectories: true)
                for path in Set(["book.json"] + manifest.assetPaths) {
                    try Task.checkCancellation()
                    let destination = try SafeBookPath.resolve(path, inside: copy)
                    try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try files.copyItem(at: SafeBookPath.resolve(path, inside: folder), to: destination)
                }
                guard try Self.editFingerprint(copy) == hash else { throw BookError.editConflict }
                return BookEditCheckout(book: LibraryBook(manifest: manifest, folder: copy), source: BookEditSource(bookID: book.id, libraryRoot: root, fingerprint: hash))
            }
            return result
        } catch { try? files.removeItem(at: workspace); throw error }
    }

    func commitEdit(_ staged: LibraryBook, source: BookEditSource, root: URL) throws {
        let files = FileManager.default
        guard source.libraryRoot.standardizedFileURL == root.standardizedFileURL, staged.id == source.bookID else { throw BookError.editConflict }
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        let matches = try coordinatedRead(root) { folder in
            try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { (try? BookManifest.load(from: $0))?.id == source.bookID }
        }
        guard matches.count == 1, let destination = matches.first else { throw BookError.editConflict }
        let cache = cacheRoot.appendingPathComponent(source.bookID.uuidString)
        let pinned = files.fileExists(atPath: cache.appendingPathComponent(".pinned").path)
        let preparedCache = cacheRoot.appendingPathComponent(".incoming-\(UUID().uuidString)")
        let previousCache = cacheRoot.appendingPathComponent(".backup-\(UUID().uuidString)")
        defer { try? files.removeItem(at: preparedCache) }
        // Prepare a complete offline copy before changing the library. Storage failure leaves both originals intact.
        if pinned {
            try files.copyItem(at: staged.folder, to: preparedCache)
            try Data().write(to: preparedCache.appendingPathComponent(".pinned"))
        }
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { folder in
            result = Result {
                guard try Self.editFingerprint(folder) == source.fingerprint else { throw BookError.editConflict }
                let incoming = root.appendingPathComponent(".incoming-\(UUID().uuidString)")
                let backup = root.appendingPathComponent(".backup-\(UUID().uuidString)")
                defer { try? files.removeItem(at: incoming) }
                try Task.checkCancellation()
                try files.copyItem(at: staged.folder, to: incoming)
                _ = try BookManifest.load(from: incoming, requireAssets: true)
                try Task.checkCancellation()
                guard try Self.editFingerprint(folder) == source.fingerprint else { throw BookError.editConflict }
                try files.moveItem(at: folder, to: backup)
                do {
                    try files.moveItem(at: incoming, to: folder)
                    if pinned {
                        try files.moveItem(at: cache, to: previousCache)
                        do { try files.moveItem(at: preparedCache, to: cache) }
                        catch { try files.moveItem(at: previousCache, to: cache); throw error }
                    }
                } catch {
                    try? files.removeItem(at: folder)
                    try files.moveItem(at: backup, to: folder)
                    throw error
                }
                try? files.removeItem(at: backup)
                if pinned { try? files.removeItem(at: previousCache) }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BookError.unavailable(String(localized: "The book could not be opened for saving.")) }
        try result.get()
        discardImport(staged)
        if !pinned { try? files.removeItem(at: cache) }
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
