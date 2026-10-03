import Foundation
import MZAppFoundation

actor LibraryRepository {
    private let files = FileManager.default
    var diagnosticLog: FeatureLogBuffer
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
                var folders: [URL] = []
                let candidates = try files.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for (index, candidate) in candidates.enumerated() {
                    do {
                        let values = try candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if values.isDirectory == true && values.isSymbolicLink != true { folders.append(candidate) }
                    } catch {
                        diagnosticLog.warning("Library folder attributes unavailable; excluding scan candidate", error: error, category: "library", metadata: ["phase": .string("scan_folder_attributes"), "folder_index": .integer(index + 1)])
                    }
                }
                return folders
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

    func asset(_ path: String, book: LibraryBook, root: URL, operationID: String = UUID().uuidString) async throws -> URL {
        var context = BookOperationDiagnostics(operationID: operationID, bookID: book.id, phase: "asset_prepare")
        context.details["asset_kind"] = .string(BookOperationDiagnostics.assetKind(path))
        let destination = try SafeBookPath.resolve(path, inside: bookCache(book.id))
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        do {
            let source = try SafeBookPath.resolve(path, inside: book.folder)
            context.phase = "asset_download"
            try await download(source, context: context)
            context.phase = "asset_cache_validate"
            let sourceValues = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            let destinationValues = try? destination.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if files.fileExists(atPath: destination.path), sourceValues.contentModificationDate == destinationValues?.contentModificationDate,
               sourceValues.fileSize == destinationValues?.fileSize {
                diagnosticLog.trace("Library asset cache is current", category: "library", metadata: context.metadata)
                return destination
            }
            context.phase = "asset_cache_copy"
            diagnosticLog.trace("Library asset cache copy started", category: "library", metadata: context.metadata)
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
            defer { removeIfPresent(temporary, operation: "asset_temporary") }
            try coordinatedRead(source, context: context) { url in
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw BookError.invalid("Missing file: \(path).") }
                try files.copyItem(at: url, to: temporary)
            }
            if files.fileExists(atPath: destination.path) { _ = try files.replaceItemAt(destination, withItemAt: temporary) }
            else { try files.moveItem(at: temporary, to: destination) }
            diagnosticLog.trace("Library asset cache copy completed", category: "library", metadata: context.metadata)
            return destination
        } catch is CancellationError { throw CancellationError() }
        catch {
            if files.fileExists(atPath: destination.path) {
                diagnosticLog.warning("Library asset refresh failed; using cached asset", error: error, category: "library", metadata: context.metadata)
                return destination
            }
            throw LibraryAssetFailure(presentation: "\(path): \(error.localizedDescription)", underlyingLogError: ErrorSnapshot(BookOperationFailure.preserving(error, context: context)))
        }
    }

    func keepOffline(_ book: LibraryBook, root: URL, operationID: String = UUID().uuidString) async throws {
        var context = BookOperationDiagnostics(operationID: operationID, bookID: book.id, phase: "offline_asset_prepare")
        context.details["asset_count"] = .integer(Set(book.manifest.assetPaths).count)
        diagnosticLog.trace("Offline book preparation started", category: "library", metadata: context.metadata)
        for path in Set(book.manifest.assetPaths).sorted() {
            try Task.checkCancellation()
            _ = try await asset(path, book: book, root: root, operationID: operationID)
        }
        context.phase = "offline_catalog_write"
        let folder = bookCache(book.id)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(book.manifest).write(to: folder.appendingPathComponent("book.json"), options: .atomic)
        try Data().write(to: folder.appendingPathComponent(".pinned"), options: .atomic)
        diagnosticLog.trace("Offline book preparation completed", category: "library", metadata: context.metadata)
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
        let context = BookOperationDiagnostics(bookID: id, phase: "remove_offline")
        diagnosticLog.trace("Offline book removal started", category: "library", metadata: context.metadata)
        removeIfPresent(bookCache(id).appendingPathComponent(".pinned"), operation: "offline_marker")
        if id != activeID, files.fileExists(atPath: bookCache(id).path) { try files.removeItem(at: bookCache(id)) }
        diagnosticLog.trace("Offline book removal completed", category: "library", metadata: context.metadata)
    }

    func clearUnpinned(protecting activeID: UUID?) throws {
        var context = BookOperationDiagnostics(phase: "clear_unpinned_cache")
        var removed = 0
        diagnosticLog.trace("Unpinned library cache cleanup started", category: "library", metadata: context.metadata)
        let pinned = pinnedIDs()
        guard files.fileExists(atPath: cacheRoot.path) else { return }
        for url in try files.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) {
            if let id = UUID(uuidString: url.lastPathComponent), !pinned.contains(id), id != activeID { try files.removeItem(at: url); removed += 1 }
        }
        context.details["removed_book_count"] = .integer(removed)
        diagnosticLog.trace("Unpinned library cache cleanup completed", category: "library", metadata: context.metadata)
    }

    func share(_ book: LibraryBook, root: URL, operationID: String = UUID().uuidString) async throws -> URL {
        var context = BookOperationDiagnostics(operationID: operationID, bookID: book.id, phase: "export_asset_prepare")
        context.details["asset_count"] = .integer(Set(book.manifest.assetPaths).count)
        diagnosticLog.trace("Book export asset preparation started", category: "library", metadata: context.metadata)
        do {
            for path in Set(book.manifest.assetPaths).sorted() { _ = try await asset(path, book: book, root: root, operationID: operationID) }
            context.phase = "export_manifest_write"
            let folder = bookCache(book.id)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(book.manifest).write(to: folder.appendingPathComponent("book.json"), options: .atomic)
            let exportFolder = files.temporaryDirectory.appendingPathComponent("BedtimeExports", isDirectory: true)
            try files.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            let title = book.manifest.title.map { "/\\:".contains($0) ? "-" : $0 }
            let url = exportFolder.appendingPathComponent(String(title.prefix(100)) + "-" + UUID().uuidString.prefix(8) + ".bedtimestory")
            context.phase = "export_archive_create"
            diagnosticLog.trace("Book export archive creation started", category: "library", metadata: context.metadata)
            try StoryArchive.create(from: folder, at: url)
            diagnosticLog.trace("Book export archive creation completed", category: "library", metadata: context.metadata)
            return url
        } catch { throw BookOperationFailure.preserving(error, context: context) }
    }

    func stageImport(_ archive: URL, operationID: String = UUID().uuidString) async throws -> LibraryBook {
        var context = BookOperationDiagnostics(operationID: operationID, phase: "import_archive_download")
        diagnosticLog.trace("Book import staging started", category: "library", metadata: context.metadata)
        let access = archive.startAccessingSecurityScopedResource()
        defer { if access { archive.stopAccessingSecurityScopedResource() } }
        try await download(archive, context: context)
        let workspace = files.temporaryDirectory.appendingPathComponent("BedtimeImport-\(UUID().uuidString)")
        try files.createDirectory(at: workspace, withIntermediateDirectories: true)
        do {
            let copy = workspace.appendingPathComponent("source.bedtimestory")
            context.phase = "import_archive_copy"
            try coordinatedRead(archive, context: context) { try files.copyItem(at: $0, to: copy) }
            let destination = workspace.appendingPathComponent("Book")
            context.phase = "import_archive_extract"
            diagnosticLog.trace("Book import archive extraction started", category: "library", metadata: context.metadata)
            try StoryArchive.extract(copy, to: destination)
            try files.removeItem(at: copy)
            context.phase = "import_manifest_validate"
            let book = LibraryBook(manifest: try BookManifest.load(from: destination, requireAssets: true), folder: destination)
            context.details["book_id"] = .string(book.id.uuidString)
            diagnosticLog.trace("Book import staging completed", category: "library", metadata: context.metadata)
            return book
        } catch { removeIfPresent(workspace, operation: "failed_import_workspace"); throw BookOperationFailure.preserving(error, context: context) }
    }

    func discardImport(_ book: LibraryBook) { removeIfPresent(book.folder.deletingLastPathComponent(), operation: "import_workspace") }

    func commitImport(_ staged: LibraryBook, root: URL, replacing: Bool, operationID: String = UUID().uuidString) throws {
        var context = BookOperationDiagnostics(operationID: operationID, bookID: staged.id, phase: "import_publish_coordinate")
        context.details["replacing"] = .bool(replacing)
        diagnosticLog.trace("Book import publication started", category: "library", metadata: context.metadata)
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: root, options: .forMerging, error: &coordinationError) { url in
            result = Result {
                context.phase = "import_publish_find_existing"
                diagnosticLog.trace("Book import file provider write access granted", category: "library", metadata: context.metadata)
                let folders = try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                let matches = folders.enumerated().compactMap { index, candidate -> URL? in
                    do { return try BookManifest.load(from: candidate).id == staged.id ? candidate : nil }
                    catch {
                        // Ordinary non-book folders have no manifest and are expected.
                        let manifest = candidate.appendingPathComponent("book.json")
                        let placeholder = candidate.appendingPathComponent(".book.json.icloud")
                        guard files.fileExists(atPath: manifest.path) || files.fileExists(atPath: placeholder.path) else { return nil }
                        var fields = context.metadata; fields["folder_index"] = .integer(index + 1)
                        diagnosticLog.warning("Book import destination manifest unavailable; excluding candidate", error: error, category: "library", metadata: fields)
                        return nil
                    }
                }
                guard matches.count <= 1 else { throw BookError.invalid("Multiple books share this identity. Resolve the duplicates in Files first.") }
                guard replacing || matches.isEmpty else { throw BookError.duplicate }
                let destination = matches.first ?? url.appendingPathComponent(staged.id.uuidString, isDirectory: true)
                guard matches.first != nil || !files.fileExists(atPath: destination.path) else { throw BookError.invalid("Destination folder is already occupied.") }
                let incoming = url.appendingPathComponent(".incoming-\(UUID().uuidString)")
                let backup = url.appendingPathComponent(".backup-\(UUID().uuidString)")
                defer { removeIfPresent(incoming, operation: "import_incoming") }
                try Task.checkCancellation()
                context.phase = "import_publish_copy"
                diagnosticLog.trace("Book import publication copy started", category: "library", metadata: context.metadata)
                try files.copyItem(at: staged.folder, to: incoming)
                try Task.checkCancellation()
                _ = try BookManifest.load(from: incoming, requireAssets: true)
                context.phase = "import_publish_replace"
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
        do { try result.get() }
        catch { throw BookOperationFailure.preserving(error, context: context) }
        discardImport(staged)
        removeIfPresent(bookCache(staged.id), operation: "import_cache")
        context.phase = "import_publish_complete"
        diagnosticLog.trace("Book import publication completed", category: "library", metadata: context.metadata)
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

    func download(_ url: URL, knownUbiquitous: Bool = false,
                  context suppliedContext: BookOperationDiagnostics? = nil) async throws {
        var context = suppliedContext ?? BookOperationDiagnostics(phase: "asset_download")
        context.details["asset_kind"] = .string(BookOperationDiagnostics.assetKind(url.lastPathComponent))
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        let exists = files.fileExists(atPath: url.path)
        let resource = !exists && files.fileExists(atPath: placeholder.path) ? placeholder : url
        var values: URLResourceValues?
        do { values = try resource.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) }
        catch {
            if files.fileExists(atPath: resource.path) {
                diagnosticLog.warning("Book asset provider attributes unavailable; continuing availability check", error: error, category: "library", metadata: context.metadata)
            } else if suppliedContext != nil || knownUbiquitous {
                let cause = ErrorSnapshot(error).causes.first
                context.details["attribute_error_domain"] = cause.map { .string($0.domain) }
                context.details["attribute_error_code"] = cause.map { .integer($0.code) }
                diagnosticLog.trace("Book asset provider attributes pending local file availability", category: "library", metadata: context.metadata)
            }
        }
        context.details["local_file_present"] = .bool(exists)
        context.details["placeholder_present"] = .bool(resource != url)
        context.details["icloud_item"] = .bool(knownUbiquitous || values?.isUbiquitousItem == true)
        context.details["download_status"] = .string(Self.downloadStatus(values?.ubiquitousItemDownloadingStatus))
        if exists, values?.isUbiquitousItem != true {
            if suppliedContext != nil { diagnosticLog.trace("Book asset already available locally", category: "library", metadata: context.metadata) }
            return
        }
        guard knownUbiquitous || values?.isUbiquitousItem == true else {
            if suppliedContext != nil { diagnosticLog.trace("Book asset has no iCloud download provider", category: "library", metadata: context.metadata) }
            return
        }
        if values?.ubiquitousItemDownloadingStatus == .current {
            if suppliedContext != nil { diagnosticLog.trace("Book iCloud asset already current", category: "library", metadata: context.metadata) }
            return
        }
        context.details["timeout_seconds"] = .integer(45)
        diagnosticLog.trace("iCloud asset download requested", category: "library", metadata: context.metadata)
        let started = ContinuousClock.now
        var nextProgress = started.advanced(by: .seconds(5))
        let deadline = started.advanced(by: .seconds(45))
        var lastStatus = context.details["download_status"]
        var lastStatusName = Self.downloadStatus(values?.ubiquitousItemDownloadingStatus)
        var reportedAttributeFailure = false
        do {
            try files.startDownloadingUbiquitousItem(at: resource)
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                var status: URLResourceValues?
                do { status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey, .ubiquitousItemIsDownloadingKey]) }
                catch {
                    if !reportedAttributeFailure {
                        reportedAttributeFailure = true
                        if files.fileExists(atPath: url.path) {
                            diagnosticLog.warning("iCloud download status attributes unavailable; continuing wait", error: error, category: "library", metadata: context.metadata)
                        } else {
                            let cause = ErrorSnapshot(error).causes.first
                            context.details["attribute_error_domain"] = cause.map { .string($0.domain) }
                            context.details["attribute_error_code"] = cause.map { .integer($0.code) }
                            diagnosticLog.trace("iCloud download status pending local file creation", category: "library", metadata: context.metadata)
                        }
                    }
                }
                let statusName = Self.downloadStatus(status?.ubiquitousItemDownloadingStatus)
                lastStatusName = statusName
                context.details["download_status"] = .string(statusName)
                context.details["provider_is_downloading"] = .bool(status?.ubiquitousItemIsDownloading == true)
                context.details["local_file_present"] = .bool(files.fileExists(atPath: url.path))
                context.details["download_elapsed_ms"] = .integer(BookOperationDiagnostics.milliseconds(since: started))
                if let error = status?.ubiquitousItemDownloadingError { throw error }
                if status?.ubiquitousItemDownloadingStatus == .current {
                    diagnosticLog.trace("iCloud asset download completed", category: "library", metadata: context.metadata)
                    return
                }
                // Provider state changes and one bounded heartbeat per five seconds
                // explain long waits without emitting a message on every poll.
                if lastStatus != .string(statusName) || ContinuousClock.now >= nextProgress {
                    diagnosticLog.trace("iCloud asset download waiting for file provider", category: "library", metadata: context.metadata)
                    lastStatus = .string(statusName)
                    nextProgress = ContinuousClock.now.advanced(by: .seconds(5))
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            diagnosticLog.trace("iCloud asset download timed out", category: "library", metadata: context.metadata)
            throw LibraryDownloadTimeout(status: lastStatusName)
        } catch {
            diagnosticLog.trace(ErrorSnapshot.isCancellation(error) ? "iCloud asset download cancelled" : "iCloud asset download interrupted", category: "library", metadata: context.metadata)
            throw BookOperationFailure.preserving(error, context: context)
        }
    }

    private static func downloadStatus(_ status: URLUbiquitousItemDownloadingStatus?) -> String {
        switch status {
        case .current: "current"
        case .downloaded: "downloaded"
        case .notDownloaded: "not_downloaded"
        default: "unknown"
        }
    }

    func coordinatedRead<T: Sendable>(_ url: URL, context: BookOperationDiagnostics? = nil, _ action: (URL) throws -> T) throws -> T {
        var error: NSError?
        var result: Result<T, Error>?
        if let context { diagnosticLog.trace("File provider read coordination requested", category: "library", metadata: context.metadata) }
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { location in
            if let context { diagnosticLog.trace("File provider read access granted", category: "library", metadata: context.metadata) }
            result = Result { try action(location) }
        }
        if let error { throw error }
        guard let result else { throw BookError.unavailable("The file provider did not grant access.") }
        let value = try result.get()
        if let context { diagnosticLog.trace("File provider coordinated read completed", category: "library", metadata: context.metadata) }
        return value
    }

}

/// Retain provider evidence while preserving the library's existing presentation.
private nonisolated struct LibraryAssetFailure: LocalizedError, LoggableError, UnderlyingErrorSnapshotProviding, Sendable {
    var logMessage: String { "A library asset could not be prepared and no cached copy is available." }
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

/// A technical timeout explanation safe to show in copied diagnostic errors.
private nonisolated struct LibraryDownloadTimeout: LocalizedError, LoggableError, Sendable {
    let status: String
    var errorDescription: String? { "iCloud has not finished downloading this file. Check your connection and try again." }
    var logMessage: String { "iCloud file provider did not make the requested asset current within 45 seconds (last status: \(status))." }
}
