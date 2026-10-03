import Foundation
import MZAppFoundation

actor LibraryRepository {
    private let files = FileManager.default
    private var diagnosticLog: FeatureLogBuffer
    let cacheRoot: URL

    init(cacheRoot: URL, logDestination: FeatureLogDestination? = nil) {
        self.cacheRoot = cacheRoot
        diagnosticLog = FeatureLogBuffer(destination: logDestination)
    }

    func flushDiagnosticLogs() async { await diagnosticLog.flush() }

    func scan(root: URL, discoveredFolders: [URL] = []) async throws -> LibraryScan {
        diagnosticLog.trace("Library provider scan started", category: "library", metadata: ["discovered_folder_count": .integer(discoveredFolders.count)])
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        let previousBooks = cachedCatalog()
        do {
            let localFolders: [URL] = try coordinatedRead(root) { url in
                try files.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false }
            }
            let prefix = root.standardizedFileURL.path + "/"
            let folders = Set(localFolders + discoveredFolders.filter { $0.standardizedFileURL.path.hasPrefix(prefix) && $0.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") })
            var books: [LibraryBook] = []
            var warnings: [String] = []
            var ids = Set<UUID>()
            for folder in folders {
                try Task.checkCancellation()
                let manifestURL = folder.appendingPathComponent("book.json")
                guard discoveredFolders.contains(folder) || files.fileExists(atPath: manifestURL.path) || files.fileExists(atPath: folder.appendingPathComponent(".book.json.icloud").path) else { continue }
                do {
                    try await download(manifestURL, knownUbiquitous: discoveredFolders.contains(folder))
                    let manifest = try coordinatedRead(folder) { try BookManifest.load(from: $0) }
                    guard ids.insert(manifest.id).inserted else { throw BookError.invalid("Duplicate book identity.") }
                    books.append(LibraryBook(manifest: manifest, folder: folder))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    diagnosticLog.warning("Library book scan failed", error: error, category: "library")
                    warnings.append("\(folder.lastPathComponent): \(error.localizedDescription)")
                    var transient = !(error is DecodingError)
                    if case BookError.invalid = error { transient = false }
                    if transient, let previous = previousBooks.first(where: { $0.folder == folder }), ids.insert(previous.id).inserted {
                        books.append(previous)
                    }
                }
            }
            books.sort { $0.manifest.title.localizedStandardCompare($1.manifest.title) == .orderedAscending }
            try files.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try JSONEncoder().encode(books).write(to: cacheRoot.appendingPathComponent("catalog.json"), options: .atomic)
            return LibraryScan(books: books, warnings: warnings, isOffline: false)
        } catch is CancellationError { throw CancellationError() }
        catch {
            diagnosticLog.warning("Library provider scan failed; using cached catalog", error: error, category: "library", metadata: ["cached_book_count": .integer(previousBooks.count)])
            return LibraryScan(books: previousBooks, warnings: [error.localizedDescription], isOffline: true)
        }
    }

    func asset(_ path: String, book: LibraryBook, root: URL) async throws -> URL {
        let destination = try SafeBookPath.resolve(path, inside: bookCache(book.id))
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        do {
            let source = try SafeBookPath.resolve(path, inside: book.folder)
            try await download(source)
            let sourceValues = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            let destinationValues = try? destination.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if files.fileExists(atPath: destination.path), sourceValues.contentModificationDate == destinationValues?.contentModificationDate,
               sourceValues.fileSize == destinationValues?.fileSize { return destination }
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
            defer { removeIfPresent(temporary, operation: "asset_temporary") }
            try coordinatedRead(source) { url in
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw BookError.invalid("Missing file: \(path).") }
                try files.copyItem(at: url, to: temporary)
            }
            if files.fileExists(atPath: destination.path) { _ = try files.replaceItemAt(destination, withItemAt: temporary) }
            else { try files.moveItem(at: temporary, to: destination) }
            return destination
        } catch is CancellationError { throw CancellationError() }
        catch {
            if files.fileExists(atPath: destination.path) {
                diagnosticLog.warning("Library asset refresh failed; using cached asset", error: error, category: "library")
                return destination
            }
            throw LibraryAssetFailure(presentation: "\(path): \(error.localizedDescription)", underlyingLogError: ErrorSnapshot(error))
        }
    }

    func keepOffline(_ book: LibraryBook, root: URL) async throws {
        for path in Set(book.manifest.assetPaths) {
            try Task.checkCancellation()
            _ = try await asset(path, book: book, root: root)
        }
        let folder = bookCache(book.id)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(book.manifest).write(to: folder.appendingPathComponent("book.json"), options: .atomic)
        try Data().write(to: folder.appendingPathComponent(".pinned"), options: .atomic)
    }

    func pinnedIDs() -> Set<UUID> {
        let folders: [URL]
        guard files.fileExists(atPath: cacheRoot.path) else { return [] }
        do { folders = try files.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) }
        catch {
            diagnosticLog.warning("Offline book catalog unavailable", error: error, category: "library")
            return []
        }
        return Set(folders.compactMap { url in
            files.fileExists(atPath: url.appendingPathComponent(".pinned").path) ? UUID(uuidString: url.lastPathComponent) : nil
        })
    }

    func removeOffline(_ id: UUID, protecting activeID: UUID?) throws {
        removeIfPresent(bookCache(id).appendingPathComponent(".pinned"), operation: "offline_marker")
        if id != activeID, files.fileExists(atPath: bookCache(id).path) { try files.removeItem(at: bookCache(id)) }
    }

    func clearUnpinned(protecting activeID: UUID?) throws {
        let pinned = pinnedIDs()
        guard files.fileExists(atPath: cacheRoot.path) else { return }
        for url in try files.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) {
            if let id = UUID(uuidString: url.lastPathComponent), !pinned.contains(id), id != activeID { try files.removeItem(at: url) }
        }
    }

    func share(_ book: LibraryBook, root: URL) async throws -> URL {
        for path in Set(book.manifest.assetPaths) { _ = try await asset(path, book: book, root: root) }
        let folder = bookCache(book.id)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(book.manifest).write(to: folder.appendingPathComponent("book.json"), options: .atomic)
        let exportFolder = files.temporaryDirectory.appendingPathComponent("BedtimeExports", isDirectory: true)
        try files.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let title = book.manifest.title.map { "/\\:".contains($0) ? "-" : $0 }
        let url = exportFolder.appendingPathComponent(String(title.prefix(100)) + "-" + UUID().uuidString.prefix(8) + ".bedtimestory")
        try StoryArchive.create(from: folder, at: url)
        return url
    }

    func stageImport(_ archive: URL) async throws -> LibraryBook {
        let access = archive.startAccessingSecurityScopedResource()
        defer { if access { archive.stopAccessingSecurityScopedResource() } }
        try await download(archive)
        let workspace = files.temporaryDirectory.appendingPathComponent("BedtimeImport-\(UUID().uuidString)")
        try files.createDirectory(at: workspace, withIntermediateDirectories: true)
        do {
            let copy = workspace.appendingPathComponent("source.bedtimestory")
            try coordinatedRead(archive) { try files.copyItem(at: $0, to: copy) }
            let destination = workspace.appendingPathComponent("Book")
            try StoryArchive.extract(copy, to: destination)
            try files.removeItem(at: copy)
            return LibraryBook(manifest: try BookManifest.load(from: destination, requireAssets: true), folder: destination)
        } catch { removeIfPresent(workspace, operation: "failed_import_workspace"); throw error }
    }

    func discardImport(_ book: LibraryBook) { removeIfPresent(book.folder.deletingLastPathComponent(), operation: "import_workspace") }

    func commitImport(_ staged: LibraryBook, root: URL, replacing: Bool) throws {
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: root, options: .forMerging, error: &coordinationError) { url in
            result = Result {
                let folders = try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                let matches = folders.filter { (try? BookManifest.load(from: $0))?.id == staged.id }
                guard matches.count <= 1 else { throw BookError.invalid("Multiple books share this identity. Resolve the duplicates in Files first.") }
                guard replacing || matches.isEmpty else { throw BookError.duplicate }
                let destination = matches.first ?? url.appendingPathComponent(staged.id.uuidString, isDirectory: true)
                guard matches.first != nil || !files.fileExists(atPath: destination.path) else { throw BookError.invalid("Destination folder is already occupied.") }
                let incoming = url.appendingPathComponent(".incoming-\(UUID().uuidString)")
                let backup = url.appendingPathComponent(".backup-\(UUID().uuidString)")
                defer { removeIfPresent(incoming, operation: "import_incoming") }
                try Task.checkCancellation()
                try files.copyItem(at: staged.folder, to: incoming)
                try Task.checkCancellation()
                _ = try BookManifest.load(from: incoming, requireAssets: true)
                if matches.first != nil { try files.moveItem(at: destination, to: backup) }
                do { try files.moveItem(at: incoming, to: destination) }
                catch {
                    if files.fileExists(atPath: backup.path) { try files.moveItem(at: backup, to: destination) }
                    throw error
                }
                removeIfPresent(backup, operation: "import_backup")
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BookError.unavailable("The folder is not available for importing.") }
        try result.get()
        discardImport(staged)
        removeIfPresent(bookCache(staged.id), operation: "import_cache")
    }

    private func cachedCatalog() -> [LibraryBook] {
        let url = cacheRoot.appendingPathComponent("catalog.json")
        guard files.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([LibraryBook].self, from: Data(contentsOf: url)) }
        catch {
            diagnosticLog.warning("Cached library catalog unavailable", error: error, category: "library")
            return []
        }
    }

    func removeIfPresent(_ url: URL, operation: String) {
        guard files.fileExists(atPath: url.path) else { return }
        do { try files.removeItem(at: url) }
        catch { diagnosticLog.warning("Library cleanup failed", error: error, category: "library", metadata: ["phase": .string(operation)]) }
    }

    private func bookCache(_ id: UUID) -> URL { cacheRoot.appendingPathComponent(id.uuidString, isDirectory: true) }

    func download(_ url: URL, knownUbiquitous: Bool = false) async throws {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        let resource = !files.fileExists(atPath: url.path) && files.fileExists(atPath: placeholder.path) ? placeholder : url
        let values = try? resource.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if files.fileExists(atPath: url.path), values?.isUbiquitousItem != true { return }
        guard knownUbiquitous || values?.isUbiquitousItem == true else { return }
        if values?.ubiquitousItemDownloadingStatus == .current { return }
        diagnosticLog.trace("iCloud asset download requested", category: "library")
        try files.startDownloadingUbiquitousItem(at: resource)
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])
            if let error = status?.ubiquitousItemDownloadingError { throw error }
            if status?.ubiquitousItemDownloadingStatus == .current {
                diagnosticLog.trace("iCloud asset download completed", category: "library")
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw BookError.unavailable("iCloud has not finished downloading this file. Check your connection and try again.")
    }

    func coordinatedRead<T>(_ url: URL, _ action: (URL) throws -> T) throws -> T {
        var error: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { location in
            result = Result { try action(location) }
        }
        if let error { throw error }
        guard let result else { throw BookError.unavailable("The file provider did not grant access.") }
        return try result.get()
    }
}

/// Retain provider evidence while preserving the library's existing presentation.
private nonisolated struct LibraryAssetFailure: LocalizedError, UnderlyingErrorSnapshotProviding, Sendable {
    let presentation: String
    let underlyingLogError: ErrorSnapshot?
    var errorDescription: String? { presentation }
}

extension LibraryRepository {
    func imageData(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30_000_000 else { throw BookError.invalid("Image is too large to display.") }
        return try Data(contentsOf: url)
    }
    func textContents(_ url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 5_000_000 else { throw BookError.invalid("Chapter text is too large to display.") }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
