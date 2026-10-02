import Foundation

actor LibraryRepository {
    private let files = FileManager.default
    let cacheRoot: URL

    init(cacheRoot: URL) { self.cacheRoot = cacheRoot }

    func scan(root: URL, discoveredFolders: [URL] = []) async throws -> LibraryScan {
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
            defer { try? files.removeItem(at: temporary) }
            try coordinatedRead(source) { url in
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw BookError.invalid("Missing file: \(path).") }
                try files.copyItem(at: url, to: temporary)
            }
            if files.fileExists(atPath: destination.path) { _ = try files.replaceItemAt(destination, withItemAt: temporary) }
            else { try files.moveItem(at: temporary, to: destination) }
            return destination
        } catch is CancellationError { throw CancellationError() }
        catch {
            if files.fileExists(atPath: destination.path) { return destination }
            throw BookError.unavailable("\(path): \(error.localizedDescription)")
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
        let folders = (try? files.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)) ?? []
        return Set(folders.compactMap { url in
            files.fileExists(atPath: url.appendingPathComponent(".pinned").path) ? UUID(uuidString: url.lastPathComponent) : nil
        })
    }

    func removeOffline(_ id: UUID, protecting activeID: UUID?) throws {
        try? files.removeItem(at: bookCache(id).appendingPathComponent(".pinned"))
        if id != activeID, files.fileExists(atPath: bookCache(id).path) { try files.removeItem(at: bookCache(id)) }
    }

    func clearUnpinned(protecting activeID: UUID?) throws {
        let pinned = pinnedIDs()
        for url in (try? files.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)) ?? [] {
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
        } catch { try? files.removeItem(at: workspace); throw error }
    }

    func discardImport(_ book: LibraryBook) { try? files.removeItem(at: book.folder.deletingLastPathComponent()) }

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
                defer { try? files.removeItem(at: incoming) }
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
                try? files.removeItem(at: backup)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BookError.unavailable("The folder is not available for importing.") }
        try result.get()
        discardImport(staged)
        try? files.removeItem(at: bookCache(staged.id))
    }

    private func cachedCatalog() -> [LibraryBook] {
        guard let data = try? Data(contentsOf: cacheRoot.appendingPathComponent("catalog.json")) else { return [] }
        return (try? JSONDecoder().decode([LibraryBook].self, from: data)) ?? []
    }

    private func bookCache(_ id: UUID) -> URL { cacheRoot.appendingPathComponent(id.uuidString, isDirectory: true) }

    func download(_ url: URL, knownUbiquitous: Bool = false) async throws {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        let resource = !files.fileExists(atPath: url.path) && files.fileExists(atPath: placeholder.path) ? placeholder : url
        let values = try? resource.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if files.fileExists(atPath: url.path), values?.isUbiquitousItem != true { return }
        guard knownUbiquitous || values?.isUbiquitousItem == true else { return }
        if values?.ubiquitousItemDownloadingStatus == .current { return }
        try files.startDownloadingUbiquitousItem(at: resource)
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])
            if let error = status?.ubiquitousItemDownloadingError { throw error }
            if status?.ubiquitousItemDownloadingStatus == .current { return }
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
