import CryptoKit
import Foundation

extension LibraryRepository {
    /// Copies old/local books without deleting originals or replacing a different destination book.
    func migrateBooks(from source: URL, to destination: URL) async throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let sourceScan = try await scan(root: source)
        guard !sourceScan.isOffline else { throw BookError.unavailable("Your previous library is unavailable. Its books have not been removed.") }
        var destinationBooks = try await scan(root: destination).books
        let receiptURL = destination.appendingPathComponent(".library-migrations.json")
        try await download(receiptURL)
        var receipts = try coordinatedRead(destination) { _ in try migrationReceipts(at: receiptURL) }
        for book in sourceScan.books {
            try Task.checkCancellation()
            let archive = try await share(book, root: source)
            defer { removeIfPresent(archive, operation: "migration_archive") }
            var staged = try await stageImport(archive)
            defer { discardImport(staged) }
            let fingerprint = try migrationFingerprint(staged)
            let key = SHA256.hash(data: Data((source.standardizedFileURL.path + book.id.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
            guard receipts[key] != fingerprint else { continue }
            if let existing = destinationBooks.first(where: { $0.id == book.id }) {
                let existingArchive = try await share(existing, root: destination)
                defer { removeIfPresent(existingArchive, operation: "migration_existing_archive") }
                let comparison = try await stageImport(existingArchive)
                defer { discardImport(comparison) }
                if try migrationFingerprint(comparison) == fingerprint {
                    receipts[key] = fingerprint
                    try saveMigrationReceipts(receipts, to: receiptURL)
                    continue
                }
                let hash = Array(SHA256.hash(data: Data((key + fingerprint).utf8)))
                staged.manifest.id = UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7], hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
                staged.manifest.title += String(localized: " (Recovered copy)")
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(staged.manifest).write(to: staged.folder.appendingPathComponent("book.json"), options: .atomic)
            }
            if !destinationBooks.contains(where: { $0.id == staged.id }) {
                try commitImport(staged, root: destination, replacing: false)
                destinationBooks.append(staged)
            }
            receipts[key] = fingerprint
            try saveMigrationReceipts(receipts, to: receiptURL)
        }
        guard sourceScan.warnings.isEmpty else { throw BookError.unavailable("Some previous books are not ready to copy. The originals are safe. Try again after their downloads finish in Files.") }
    }

    private func migrationFingerprint(_ book: LibraryBook) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var hash = SHA256()
        hash.update(data: try encoder.encode(book.manifest))
        for path in Set(book.manifest.assetPaths).sorted() {
            hash.update(data: Data(path.utf8))
            let url = try SafeBookPath.resolve(path, inside: book.folder)
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
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
