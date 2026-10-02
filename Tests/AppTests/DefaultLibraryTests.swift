import Foundation
import Synchronization
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct DefaultLibraryTests {
    @Test func consentPrecedesAutomaticCreationAndCloudMigrationPreservesBooksAndProgress() async throws {
        let workspace = root()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let local = workspace.appendingPathComponent("LocalBooks")
        let cloud = workspace.appendingPathComponent("Cloud")
        let state = ContainerState()
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let storage = DefaultLibraryStorage(localRoot: local, container: { state.value }, identity: { "qa-account" })
        let model = LibraryModel(defaults: defaults, storage: storage)
        await model.start()
        #expect(model.root == nil && !FileManager.default.fileExists(atPath: local.path))
        await model.acceptDefaultLibrary()
        #expect(model.root == local && !model.cloudStorage)
        let book = try makeBook(root: local, title: "Local book")
        await model.refresh()
        model.progress.saveReading(book.manifest.orderedChapters[0].id, bookID: book.id)
        state.value = cloud
        await model.start()
        #expect(model.root == cloud.appendingPathComponent("Documents/Books", isDirectory: true))
        #expect(model.cloudStorage && model.books.map(\.id) == [book.id])
        #expect(model.progress.readingChapter(book.id) == book.manifest.orderedChapters[0].id)
        #expect(FileManager.default.fileExists(atPath: book.folder.appendingPathComponent("book.json").path))
        let reopened = LibraryModel(defaults: defaults, storage: storage)
        await reopened.start()
        #expect(reopened.books.map(\.id) == [book.id])
        #expect(reopened.progress.readingChapter(book.id) == book.manifest.orderedChapters[0].id)
    }

    @Test func legacyBookmarkIsCopiedWithoutDeletingOriginalOrLosingReadingPosition() async throws {
        let workspace = root()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("PreviouslySelected")
        let book = try makeBook(root: source, title: "Previous book")
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set("legacy-progress", forKey: "libraryNamespace")
        defaults.set(try source.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "libraryFolder")
        LocalProgress(namespace: "legacy-progress", defaults: defaults).saveReading(book.manifest.orderedChapters[0].id, bookID: book.id)
        let storage = DefaultLibraryStorage(localRoot: workspace.appendingPathComponent("Default"), container: { nil })
        let model = LibraryModel(defaults: defaults, storage: storage)
        await model.acceptDefaultLibrary()
        #expect(model.books.map(\.id) == [book.id])
        #expect(model.migrationMessage == nil && defaults.bool(forKey: "defaultLibraryLegacyMigrated"))
        #expect(model.progress.readingChapter(book.id) == book.manifest.orderedChapters[0].id)
        #expect(try BookManifest.load(from: book.folder) == book.manifest)
    }

    @Test func migrationPreservesConflictingVersionsAndNeverResurrectsAnUnchangedDeletedCopy() async throws {
        let workspace = root()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source")
        let destination = workspace.appendingPathComponent("Destination")
        let original = try makeBook(root: source, title: "Original")
        let existing = try makeBook(root: destination, title: "Changed", id: original.id)
        let repository = LibraryRepository(cacheRoot: workspace.appendingPathComponent("Cache"))
        try await repository.migrateBooks(from: source, to: destination)
        var books = try await repository.scan(root: destination).books
        #expect(books.count == 2 && books.contains { $0.id == existing.id && $0.manifest.title == "Changed" })
        let recovered = try #require(books.first { $0.id != original.id })
        #expect(recovered.manifest.title.contains("Original"))
        try await repository.migrateBooks(from: source, to: destination)
        #expect(try await repository.scan(root: destination).books.count == 2)
        try FileManager.default.removeItem(at: recovered.folder)
        try await repository.migrateBooks(from: source, to: destination)
        books = try await repository.scan(root: destination).books
        #expect(books.count == 1 && books[0].manifest.title == "Changed")
        #expect(try BookManifest.load(from: original.folder).title == "Original")
    }

    @Test func unavailableMigrationSourceLeavesDestinationUntouchedAndCanBeRetried() async throws {
        let workspace = root()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Destination")
        let existing = try makeBook(root: destination, title: "Safe")
        let repository = LibraryRepository(cacheRoot: workspace.appendingPathComponent("Cache"))
        do {
            try await repository.migrateBooks(from: workspace.appendingPathComponent("Missing"), to: destination)
            Issue.record("Unavailable source should remain pending")
        } catch { }
        #expect(try await repository.scan(root: destination).books.map(\.id) == [existing.id])
    }

    @Test func metadataDiscoveryIncludesNestedBooksAndRejectsOutsideLibraryPaths() async throws {
        let workspace = root()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Books")
        let nested = try makeBook(root: destination.appendingPathComponent("Family"), title: "Discovered")
        let outside = try makeBook(root: workspace.appendingPathComponent("Outside"), title: "Outside")
        let repository = LibraryRepository(cacheRoot: workspace.appendingPathComponent("Cache"))
        let books = try await repository.scan(root: destination, discoveredFolders: [nested.folder, outside.folder]).books
        #expect(books.map(\.id) == [nested.id])
    }

    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DefaultLibraryTests-\(UUID().uuidString)") }
    private func makeBook(root: URL, title: String, id: UUID = UUID()) throws -> LibraryBook {
        let folder = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("A quiet story for bedtime.".utf8).write(to: folder.appendingPathComponent("story.md"))
        let manifest = BookManifest(id: id, title: title, chapters: [BookChapter(title: "Home", text: "story.md")])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("book.json"))
        return LibraryBook(manifest: manifest, folder: folder)
    }
    private final class ContainerState: Sendable {
        private let lock = Mutex<URL?>(nil)
        var value: URL? {
            get { lock.withLock { $0 } }
            set { lock.withLock { $0 = newValue } }
        }
    }
}
