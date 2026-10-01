import Foundation
import Observation
import UIKit

@Observable @MainActor
final class LibraryModel {
    private(set) var books: [LibraryBook] = []
    private(set) var root: URL?
    private(set) var refreshing = false
    private(set) var offline = false
    private(set) var pinned = Set<UUID>()
    private(set) var warnings: [String] = []
    private(set) var revision = 0
    var message: String?
    var activity: String?
    var importCandidate: LibraryBook?
    var shareURL: URL?
    var selectedBook: LibraryBook?
    var showingSettings = false
    var showingFolderPicker = false
    var showingImportPicker = false
    var showingPlayer = false
    var search = ""
    private(set) var repository: LibraryRepository
    private(set) var progress: LocalProgress
    let player = StoryPlayer()
    @ObservationIgnored private var presenter: FolderPresenter?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var folderAccess = false
    @ObservationIgnored private var restoredPlayback = false
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private var session = UUID()

    init() {
        let namespace = UserDefaults.standard.string(forKey: "libraryNamespace") ?? UUID().uuidString
        UserDefaults.standard.set(namespace, forKey: "libraryNamespace")
        progress = LocalProgress(namespace: namespace)
        repository = LibraryRepository(cacheRoot: Self.cacheURL(namespace))
        if let bookmark = UserDefaults.standard.data(forKey: "libraryFolder") {
            do {
                var stale = false
                let folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                folderAccess = folder.startAccessingSecurityScopedResource()
                root = folder
                if stale { try saveBookmark(folder) }
                observe(folder)
            } catch { message = error.localizedDescription }
        }
    }

    var filteredBooks: [LibraryBook] {
        guard !search.isEmpty else { return books }
        return books.filter { $0.manifest.title.localizedStandardContains(search) || ($0.manifest.author?.localizedStandardContains(search) ?? false) }
    }

    func selectFolder(_ folder: URL) async {
        guard activity == nil else { return }
        let access = folder.startAccessingSecurityScopedResource()
        do {
            guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw BookError.invalid("Choose a folder in Files.") }
            let bookmark = try folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            let sameFolder = root?.standardizedFileURL == folder.standardizedFileURL
            player.stop()
            operationTask?.cancel(); debounce?.cancel()
            if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
            if let root, folderAccess { root.stopAccessingSecurityScopedResource() }
            session = UUID()
            folderAccess = access
            root = folder
            let namespace = sameFolder ? (UserDefaults.standard.string(forKey: "libraryNamespace") ?? UUID().uuidString) : UUID().uuidString
            UserDefaults.standard.set(namespace, forKey: "libraryNamespace")
            UserDefaults.standard.set(bookmark, forKey: "libraryFolder")
            repository = LibraryRepository(cacheRoot: Self.cacheURL(namespace))
            progress = LocalProgress(namespace: namespace)
            books = []; images = [:]; selectedBook = nil; restoredPlayback = false; refreshing = false; warnings = []; offline = false
            observe(folder)
            await refresh()
        } catch {
            if access { folder.stopAccessingSecurityScopedResource() }
            message = error.localizedDescription
        }
    }

    func start() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--qa-library") {
            let fixture = URL.documentsDirectory.appendingPathComponent("QA Library", isDirectory: true)
            if FileManager.default.fileExists(atPath: fixture.path) {
                await selectFolder(fixture)
                if arguments.contains("--qa-book"), let book = books.first(where: { $0.id.uuidString == "11111111-1111-4111-8111-111111111111" }) {
                    selectedBook = book
                    if arguments.contains("--qa-player") { listen(book) }
                }
                return
            }
        }
        #endif
        await refresh()
    }

    func refresh() async {
        guard let root, !refreshing, activity == nil else { return }
        let token = session
        let repo = repository
        refreshing = true
        defer { if token == session { refreshing = false } }
        do {
            let scan = try await repo.scan(root: root)
            guard token == session else { return }
            books = scan.books; warnings = scan.warnings; offline = scan.isOffline
            pinned = await repo.pinnedIDs(); images = [:]; revision += 1
            if let selection = selectedBook { selectedBook = books.first { $0.id == selection.id } }
            if !restoredPlayback {
                restoredPlayback = true
                if let id = progress.lastBookID, let book = books.first(where: { $0.id == id }), book.manifest.hasAudio {
                    player.restore(book: book, repository: repo, root: root, progress: progress)
                }
            }
        } catch is CancellationError { }
        catch { message = error.localizedDescription }
    }

    func image(_ path: String?, book: LibraryBook) async -> UIImage? {
        guard let path, let root else { return nil }
        let key = book.id.uuidString + path
        if let image = images[key] { return image }
        do {
            let url = try await repository.asset(path, book: book, root: root)
            let data = try await repository.imageData(url)
            guard !Task.isCancelled else { return nil }
            let decoded = await ArtworkDecoder.thumbnail(data)
            let image = decoded.map { UIImage(cgImage: $0) }
            images[key] = image
            return image
        } catch { return nil }
    }

    func text(_ path: String, book: LibraryBook) async throws -> String {
        guard let root else { throw BookError.unavailable("Select your library folder first.") }
        let url = try await repository.asset(path, book: book, root: root)
        return try await repository.textContents(url)
    }

    func listen(_ book: LibraryBook, chapter: BookChapter? = nil) {
        guard let root else { return }
        showingPlayer = true
        player.play(book: book, chapter: chapter, repository: repository, root: root, progress: progress)
    }

    func keepOffline(_ book: LibraryBook) {
        perform("Downloading book…") { [self] in
            guard let root else { return }
            try await repository.keepOffline(book, root: root)
            pinned = await repository.pinnedIDs()
        }
    }

    func removeOffline(_ book: LibraryBook) {
        perform("Updating downloads…") { [self] in
            try await repository.removeOffline(book.id, protecting: player.book?.id)
            pinned = await repository.pinnedIDs()
        }
    }

    func share(_ book: LibraryBook) {
        perform("Preparing book…") { [self] in
            guard let root else { return }
            shareURL = try await repository.share(book, root: root)
        }
    }

    func importBook(_ url: URL) {
        guard root != nil else {
            message = String(localized: "Select your library folder, then open the book again.")
            return
        }
        perform("Opening book…") { [self] in
            let staged = try await repository.stageImport(url)
            importCandidate = staged
        }
    }

    func commitImport(replacing: Bool) {
        guard let candidate = importCandidate else { return }
        importCandidate = nil
        perform("Importing book…") { [self] in
            guard let root else { return }
            do {
                try await repository.commitImport(candidate, root: root, replacing: replacing)
                if player.book?.id == candidate.id { player.stop() }
            } catch BookError.duplicate { importCandidate = candidate }
            catch { await repository.discardImport(candidate); throw error }
        }
    }

    func cancelImport() {
        if let book = importCandidate { Task { await repository.discardImport(book) } }
        importCandidate = nil
    }

    func clearCache() {
        perform("Clearing cache…") { [self] in try await repository.clearUnpinned(protecting: player.book?.id) }
    }

    func cancelOperation() { operationTask?.cancel() }

    private func perform(_ label: String, operation: @escaping @MainActor () async throws -> Void) {
        guard activity == nil else { return }
        activity = NSLocalizedString(label, comment: "")
        operationTask = Task {
            do { try await operation() }
            catch is CancellationError { }
            catch { message = error.localizedDescription }
            activity = nil
            await refresh()
        }
    }

    private func observe(_ folder: URL) {
        let token = session
        let observer = FolderPresenter(url: folder) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.debounce?.cancel()
                self.debounce = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(500)) }
                    catch { return }
                    await self?.refresh()
                }
            }
        }
        presenter = observer
        NSFileCoordinator.addFilePresenter(observer)
    }

    private func saveBookmark(_ folder: URL) throws {
        UserDefaults.standard.set(try folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "libraryFolder")
    }

    private static func cacheURL(_ namespace: String) -> URL {
        let base = URL.applicationSupportDirectory.appendingPathComponent("LibraryCache/" + namespace, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return base
    }

    isolated deinit {
        debounce?.cancel(); operationTask?.cancel()
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        if let root, folderAccess { root.stopAccessingSecurityScopedResource() }
    }
}
