import CryptoKit
import Foundation

extension LibraryRepository {
    /// Copies old/local books without deleting originals or replacing a different destination book.
    func migrateBooks(from source: URL, to destination: URL) async throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        var context = BookOperationDiagnostics(phase: "migration_source_scan")
        diagnosticLog.trace("Library migration started", category: "library", metadata: context.metadata)
        do {
            let sourceScan = try await scan(root: source)
            guard !sourceScan.isOffline else { throw BookError.unavailable("Your previous library is unavailable. Its books have not been removed.") }
            context.details["source_book_count"] = .integer(sourceScan.books.count)
            context.phase = "migration_destination_scan"
            var destinationBooks = try await scan(root: destination).books
            context.details["destination_book_count"] = .integer(destinationBooks.count)
            let receiptURL = destination.appendingPathComponent(".library-migrations.json")
            context.phase = "migration_receipt_download"
            try await download(receiptURL)
            context.phase = "migration_receipt_read"
            var receipts = try coordinatedRead(destination) { _ in try migrationReceipts(at: receiptURL) }
            diagnosticLog.trace("Library migration catalogs prepared", category: "library", metadata: context.metadata)
            var imported = 0
            var skipped = 0
            var recovered = 0
            for (index, book) in sourceScan.books.enumerated() {
                try Task.checkCancellation()
                context.details["book_id"] = .string(book.id.uuidString)
                context.details["book_index"] = .integer(index)
                context.details["asset_count"] = .integer(Set(book.manifest.assetPaths).count)
                context.phase = "migration_source_export"
                diagnosticLog.trace("Library migration book started", category: "library", metadata: context.metadata)
                let archive = try await share(book, root: source)
                defer { removeIfPresent(archive, operation: "migration_archive") }
                context.phase = "migration_archive_stage"
                var staged = try await stageImport(archive)
                defer { discardImport(staged) }
                context.phase = "migration_source_fingerprint"
                let fingerprint = try migrationFingerprint(staged)
                let key = SHA256.hash(data: Data((source.standardizedFileURL.path + book.id.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
                guard receipts[key] != fingerprint else {
                    skipped += 1
                    context.details["skip_reason"] = .string("receipt_matches")
                    diagnosticLog.trace("Library migration book already copied", category: "library", metadata: context.metadata)
                    context.details["skip_reason"] = nil
                    continue
                }
                if let existing = destinationBooks.first(where: { $0.id == book.id }) {
                    context.phase = "migration_destination_compare"
                    let existingArchive = try await share(existing, root: destination)
                    defer { removeIfPresent(existingArchive, operation: "migration_existing_archive") }
                    let comparison = try await stageImport(existingArchive)
                    defer { discardImport(comparison) }
                    if try migrationFingerprint(comparison) == fingerprint {
                        skipped += 1
                        receipts[key] = fingerprint
                        context.phase = "migration_receipt_save"
                        try saveMigrationReceipts(receipts, to: receiptURL)
                        context.details["skip_reason"] = .string("destination_matches")
                        diagnosticLog.trace("Library migration book already copied", category: "library", metadata: context.metadata)
                        context.details["skip_reason"] = nil
                        continue
                    }
                    context.phase = "migration_recovered_identity"
                    let hash = Array(SHA256.hash(data: Data((key + fingerprint).utf8)))
                    staged.manifest.id = UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7], hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
                    staged.manifest.title += String(localized: " (Recovered copy)")
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    try encoder.encode(staged.manifest).write(to: staged.folder.appendingPathComponent("book.json"), options: .atomic)
                    recovered += 1
                    context.details["recovered_book_id"] = .string(staged.id.uuidString)
                    diagnosticLog.trace("Library migration recovered a conflicting book", category: "library", metadata: context.metadata)
                }
                if !destinationBooks.contains(where: { $0.id == staged.id }) {
                    context.phase = "migration_book_commit"
                    try commitImport(staged, root: destination, replacing: false)
                    destinationBooks.append(staged)
                    imported += 1
                }
                receipts[key] = fingerprint
                context.phase = "migration_receipt_save"
                try saveMigrationReceipts(receipts, to: receiptURL)
                diagnosticLog.trace("Library migration book completed", category: "library", metadata: context.metadata)
                context.details["recovered_book_id"] = nil
            }
            context.phase = "migration_source_warnings"
            guard sourceScan.warnings.isEmpty else { throw BookError.unavailable("Some previous books are not ready to copy. The originals are safe. Try again after their downloads finish in Files.") }
            context.phase = "migration_completed"
            context.details["book_id"] = nil
            context.details["book_index"] = nil
            context.details["asset_count"] = nil
            context.details["imported_book_count"] = .integer(imported)
            context.details["skipped_book_count"] = .integer(skipped)
            context.details["recovered_book_count"] = .integer(recovered)
            diagnosticLog.trace("Library migration completed", category: "library", metadata: context.metadata)
        } catch {
            throw BookOperationFailure.preserving(error, context: context)
        }
    }

    private func migrationFingerprint(_ book: LibraryBook) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var hash = SHA256()
        hash.update(data: try encoder.encode(book.manifest))
        for path in Set(book.manifest.assetPaths).sorted() {
            hash.update(data: Data(path.utf8))
            let url = try SafeBookPath.resolve(path, inside: book.folder)
            let file = try FileHandle(forReadingFrom: url)
            defer {
                do { try file.close() }
                catch {
                    diagnosticLog.warning("Library migration asset handle cleanup failed", error: error, category: "library", metadata: [
                        "book_id": .string(book.id.uuidString), "asset_kind": .string(BookOperationDiagnostics.assetKind(path))
                    ])
                }
            }
            while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func migrationReceipts(at url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private func saveMigrationReceipts(_ receipts: [String: String], to url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { location in
            result = Result {
                var merged = try migrationReceipts(at: location)
                merged.merge(receipts) { _, new in new }
                try JSONEncoder().encode(merged).write(to: location, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BookError.unavailable("Library migration could not be saved. The originals are safe.") }
        try result.get()
    }
}
