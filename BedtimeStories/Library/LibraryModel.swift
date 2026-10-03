import Foundation
import MZAppFoundation
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
    private(set) var preparingLibrary = false
    private(set) var cloudStorage = false
    private(set) var migrationMessage: String?
    var message: String?
    var activity: String?
    var importCandidate: LibraryBook?
    var shareURL: URL?
    var selectedBook: LibraryBook?
    var showingSettings = false
    var showingImportPicker = false
    var showingPlayer = false
    var showingCreator = false
    var editingDraft: BookDraft?
    var search = ""
    private(set) var repository: LibraryRepository
    private(set) var progress: LocalProgress
    let player: StoryPlayer
    @ObservationIgnored private let logger: any AppLogging
    @ObservationIgnored private var presenter: FolderPresenter?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: DefaultLibraryStorage
    @ObservationIgnored private var location: LibraryLocation?
    @ObservationIgnored private var cloudObserver: CloudLibraryObserver?
    @ObservationIgnored private var discoveredFolders: [URL] = []
    @ObservationIgnored private var migrationPending = false
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var pendingImport: URL?
    @ObservationIgnored private var restoredPlayback = false
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private var session = UUID()

    init(defaults: UserDefaults = .standard, storage: DefaultLibraryStorage = DefaultLibraryStorage(),
         logger: any AppLogging = AppLog.logger) {
        self.logger = logger
        player = StoryPlayer(logger: logger)
        self.defaults = defaults
        self.storage = storage
        let namespace = defaults.string(forKey: "libraryNamespace") ?? UUID().uuidString
        defaults.set(namespace, forKey: "libraryNamespace")
        progress = LocalProgress(namespace: namespace, defaults: defaults)
        repository = LibraryRepository(cacheRoot: Self.cacheURL(namespace), logDestination: FeatureLogDestination(logger: logger))
    }

    var filteredBooks: [LibraryBook] {
        guard !search.isEmpty else { return books }
        return books.filter { $0.manifest.title.localizedStandardContains(search) || ($0.manifest.author?.localizedStandardContains(search) ?? false) }
    }

    func acceptDefaultLibrary() async {
        defaults.set(true, forKey: "defaultLibraryAccepted")
        await start()
    }

    func start() async {
        guard !preparingLibrary, activity == nil else { return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--qa-library") {
            let fixture = URL.documentsDirectory.appendingPathComponent("QA Library", isDirectory: true)
            if FileManager.default.fileExists(atPath: fixture.path) {
                activate(LibraryLocation(root: fixture, isCloud: false, account: "qa"))
                await refresh()
                if arguments.contains("--qa-book"), let book = books.first(where: { $0.id.uuidString == "11111111-1111-4111-8111-111111111111" }) {
                    selectedBook = book
                    if arguments.contains("--qa-player") { listen(book) }
                }
                return
            }
        }
        #endif
        guard defaults.bool(forKey: "defaultLibraryAccepted") else { return }
        preparingLibrary = true
        defer { preparingLibrary = false; if refreshPending { refreshPending = false; scheduleRefresh() } }
        do {
            let next = try await storage.prepare()
            let changed = location != next
            if changed { activate(next) }
            if changed || migrationPending {
                migrationPending = false; migrationMessage = nil
                do {
                    if let bookmark = defaults.data(forKey: "libraryFolder"), !defaults.bool(forKey: "defaultLibraryLegacyMigrated") {
                        var stale = false
                        let previous = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                        try await repository.migrateBooks(from: previous, to: next.root)
                        defaults.set(true, forKey: "defaultLibraryLegacyMigrated")
                    }
                    let local = storage.localRoot
                    if next.isCloud, FileManager.default.fileExists(atPath: local.path) {
                        try await repository.migrateBooks(from: local, to: next.root)
                    }
                } catch is CancellationError { migrationPending = true; throw CancellationError() }
                catch {
                    logger.log(LogEntry("Library migration deferred", level: .warning, category: "library",
                                        error: ErrorSnapshot(error)))
                    migrationPending = true
                    migrationMessage = String(localized: "Some existing books could not be copied yet. Their originals are safe. Check their downloads in Files, then retry library setup.")
                }
            }
            await refresh(allowWhilePreparing: true)
            if let url = pendingImport { pendingImport = nil; preparingLibrary = false; importBook(url) }
        } catch is CancellationError { logger.trace("Library setup cancelled", category: "library") }
        catch {
            logger.error("Library setup failed", error: error, category: "library")
            message = String(localized: "Your library could not be opened. Check available storage and iCloud Drive in Settings, then try again.")
        }
    }

    private func activate(_ next: LibraryLocation) {
        guard location != next else { return }
        player.stop(); operationTask?.cancel(); debounce?.cancel()
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        cloudObserver?.stop()
        session = UUID(); root = next.root; location = next; cloudStorage = next.isCloud
        logger.log(LogEntry("Library activated", category: "library", metadata: ["icloud": .bool(next.isCloud)]))
        var namespaces = defaults.dictionary(forKey: "defaultLibraryNamespaces") as? [String: String] ?? [:]
        let namespace = namespaces[next.account] ?? (namespaces.isEmpty || (namespaces.count == 1 && namespaces["device"] != nil) ? defaults.string(forKey: "libraryNamespace") ?? UUID().uuidString : UUID().uuidString)
        namespaces[next.account] = namespace
        defaults.set(namespaces, forKey: "defaultLibraryNamespaces")
        repository = LibraryRepository(cacheRoot: Self.cacheURL(namespace), logDestination: FeatureLogDestination(logger: logger))
        progress = LocalProgress(namespace: namespace, defaults: defaults)
        books = []; images = [:]; selectedBook = nil; restoredPlayback = false; refreshing = false; warnings = []; offline = false; discoveredFolders = []
        observe(next.root)
        if next.isCloud {
            let token = session
            cloudObserver = CloudLibraryObserver(root: next.root, logger: logger) { [weak self] folders in
                guard let self, self.session == token else { return }
                self.discoveredFolders = folders
                self.scheduleRefresh()
            }
        }
    }

    func refresh(allowWhilePreparing: Bool = false) async {
        guard let root, !refreshing, activity == nil, !preparingLibrary || allowWhilePreparing else { return }
        let discovered = discoveredFolders
        let token = session
        let repo = repository
        refreshing = true
        defer { if token == session { refreshing = false; if discovered != discoveredFolders { scheduleRefresh() } } }
        do {
            let scan = try await repo.scan(root: root, discoveredFolders: discovered)
            guard token == session else { return }
            books = scan.books; warnings = scan.warnings; offline = scan.isOffline
            logger.log(LogEntry("Library scan completed", level: .debug, category: "library", metadata: [
                "book_count": .integer(scan.books.count), "warning_count": .integer(scan.warnings.count),
                "offline": .bool(scan.isOffline)
            ]))
            pinned = await repo.pinnedIDs(); images = [:]; revision += 1
            if let selection = selectedBook { selectedBook = books.first { $0.id == selection.id } }
            if !restoredPlayback {
                restoredPlayback = true
                if let id = progress.lastBookID, let book = books.first(where: { $0.id == id }), book.manifest.hasAudio {
                    player.restore(book: book, repository: repo, root: root, progress: progress)
                }
            }
        } catch is CancellationError { logger.trace("Library scan cancelled", category: "library") }
        catch {
            logger.error("Library scan failed", error: error, category: "library")
            message = error.localizedDescription
        }
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
            if decoded == nil { logger.warning("Book artwork could not be decoded", category: "library") }
            let image = decoded.map { UIImage(cgImage: $0) }
            images[key] = image
            return image
        } catch is CancellationError { return nil }
        catch {
            logger.log(LogEntry("Book artwork unavailable", level: .warning, category: "library",
                                error: ErrorSnapshot(error)))
            return nil
        }
    }

    func text(_ path: String, book: LibraryBook) async throws -> String {
        guard let root else { throw BookError.unavailable("Your library is still opening. Try again in a moment.") }
        let url = try await repository.asset(path, book: book, root: root)
        return try await repository.textContents(url)
    }

    func listen(_ book: LibraryBook, chapter: BookChapter? = nil) {
        guard let root else { return }
        showingPlayer = true
        player.play(book: book, chapter: chapter, repository: repository, root: root, progress: progress)
    }

    func keepOffline(_ book: LibraryBook) {
        perform("Downloading book…", phase: "keep_offline") { [self] in
            guard let root else { return }
            try await repository.keepOffline(book, root: root)
            pinned = await repository.pinnedIDs()
        }
    }

    func removeOffline(_ book: LibraryBook) {
        perform("Updating downloads…", phase: "remove_offline") { [self] in
            try await repository.removeOffline(book.id, protecting: player.book?.id)
            pinned = await repository.pinnedIDs()
        }
    }

    func share(_ book: LibraryBook) {
        perform("Preparing book…", phase: "share") { [self] in
            guard let root else { return }
            shareURL = try await repository.share(book, root: root)
        }
    }

    func importBook(_ url: URL) {
        guard root != nil else {
            pendingImport = url
            return
        }
        perform("Opening book…", phase: "stage_import") { [self] in
            let staged = try await repository.stageImport(url)
            importCandidate = staged
        }
    }

    func commitImport(replacing: Bool) {
        guard let candidate = importCandidate else { return }
        importCandidate = nil
        perform("Importing book…", phase: "commit_import") { [self] in
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
        perform("Clearing cache…", phase: "clear_cache") { [self] in try await repository.clearUnpinned(protecting: player.book?.id) }
    }

    func createBook() {
        guard activity == nil, !preparingLibrary else { return }
        player.stop()
        showingCreator = true
    }

    func editBook(_ book: LibraryBook) {
        perform("Opening book for editing…", phase: "edit") { [self] in
            guard let root else { throw BookError.unavailable("Your library is still opening. Try again in a moment.") }
            let token = session; let account = location?.account
            if player.book?.id == book.id { player.stop() }
            let checkout = try await repository.checkout(book, root: root)
            do {
                guard token == session else { throw BookError.editConflict }
                let source = BookEditSource(bookID: checkout.source.bookID, libraryRoot: checkout.source.libraryRoot, fingerprint: checkout.source.fingerprint, libraryAccount: account)
                let draft = try await BookDraftStore.shared.createEditingDraft(BookEditCheckout(book: checkout.book, source: source))
                guard token == session else { throw BookError.editConflict }
                editingDraft = draft
                await repository.discardImport(checkout.book)
            } catch { await repository.discardImport(checkout.book); throw error }
        }
    }

    func addCreatedBook(_ book: LibraryBook) async throws {
        try await saveBook(book, source: nil)
    }

    func saveBook(_ book: LibraryBook, source: BookEditSource?) async throws {
        guard let root, activity == nil, !preparingLibrary else { throw BookError.unavailable("Your library is still opening. Try again in a moment.") }
        if let account = source?.libraryAccount, account != location?.account { throw BookError.editConflict }
        activity = String(localized: "Saving book…")
        do {
            if let source {
                if player.book?.id == book.id { player.stop() }
                try await repository.commitEdit(book, source: source, root: root)
            } else { try await repository.commitImport(book, root: root, replacing: false) }
        } catch { activity = nil; throw error }
        activity = nil
        await refresh()
        selectedBook = books.first { $0.id == book.id }
    }

    func cancelOperation() { operationTask?.cancel() }

    private func perform(_ label: String, phase: String, operation: @escaping @MainActor () async throws -> Void) {
        guard activity == nil, !preparingLibrary else { return }
        activity = NSLocalizedString(label, comment: "")
        logger.trace("Library operation started", category: "library", metadata: ["phase": .string(phase)])
        operationTask = Task {
            do {
                try await operation()
                logger.log(LogEntry("Library operation completed", category: "library", metadata: ["phase": .string(phase)]))
            }
            catch is CancellationError { logger.trace("Library operation cancelled", category: "library", metadata: ["phase": .string(phase)]) }
            catch {
                logger.error("Library operation failed", error: error, category: "library", metadata: ["phase": .string(phase)])
                message = error.localizedDescription
            }
            activity = nil
            await refresh()
        }
    }

    private func observe(_ folder: URL) {
        let token = session
        let observer = FolderPresenter(url: folder) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.scheduleRefresh()
            }
        }
        presenter = observer
        NSFileCoordinator.addFilePresenter(observer)
    }

    private func scheduleRefresh() {
        guard !preparingLibrary else { refreshPending = true; return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            await self?.refresh()
        }
    }

    private static func cacheURL(_ namespace: String) -> URL {
        let base = URL.applicationSupportDirectory.appendingPathComponent("LibraryCache/" + namespace, isDirectory: true)
        do { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        catch { AppLog.warning("Library cache directory preparation failed", error: error, category: "library") }
        var url = base
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        do { try url.setResourceValues(values) }
        catch { AppLog.warning("Library cache backup exclusion failed", error: error, category: "library") }
        return base
    }

    isolated deinit {
        debounce?.cancel(); operationTask?.cancel()
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        cloudObserver?.stop()
    }
}
