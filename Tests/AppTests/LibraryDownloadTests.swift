import Foundation
import MZAppFoundation
import Testing
@testable import BedtimeStories

@MainActor struct LibraryDownloadTests {
    @Test func editCheckoutObservesImageArrivalInsteadOfTimingOutOnCachedMetadata() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("Library")
        let folder = library.appendingPathComponent("Book")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appendingPathComponent("private-image.jpg")
        try Data([1]).write(to: image)
        let manifest = BookManifest(title: "Private title", chapters: [BookChapter(image: "private-image.jpg")])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("book.json"))
        // Model the reported provider: a local image exists, status starts as
        // not_downloaded and the provider is idle. Delivery changes its bytes.
        let provider = LibraryDownloadProvider(readState: { url in
            var state = try LibraryDownloadProvider.liveState(url)
            if url.pathExtension == "jpg" {
                state.isUbiquitousItem = true
                state.status = state.fileSize == 2 ? "current" : "not_downloaded"
            }
            return state
        }, requestDownload: { url in try Data([1, 2]).write(to: url) },
           timeout: .seconds(1), pollInterval: .milliseconds(1))
        let repository = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"), downloadProvider: provider)
        let checkout = try await repository.checkout(LibraryBook(manifest: manifest, folder: folder), root: library)
        #expect(try Data(contentsOf: checkout.book.folder.appendingPathComponent("private-image.jpg")) == Data([1, 2]))
        await repository.discardImport(checkout.book)
    }

    @Test func stalledProviderFailureRetainsAssetStateAndQuotaCauseInTheBoundaryLog() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("private-child-name.jpg")
        try Data([1]).write(to: image)
        let chapter = BookChapter(image: image.lastPathComponent)
        let manifest = BookManifest(title: "Private story", chapters: [chapter])
        var context = BookOperationDiagnostics(bookID: manifest.id, phase: "checkout_asset_download")
        context.identifyAsset(image.lastPathComponent, manifest: manifest)
        context.details["asset_index"] = .integer(4)
        let error = NSError(domain: "NSFileProviderErrorDomain", code: -1003,
                            userInfo: [NSLocalizedDescriptionKey: "Private account and provider response"])
        let provider = LibraryDownloadProvider(readState: { _ in
            .init(isUbiquitousItem: true, status: "not_downloaded", fileSize: 1, isRegularFile: true,
                  isUploaded: false, isUploading: false, uploadError: error)
        }, requestDownload: { _ in }, timeout: .zero)
        let sink = RecordingLogger()
        let repository = LibraryRepository(cacheRoot: root, logDestination: FeatureLogDestination(logger: sink), downloadProvider: provider)
        do {
            try await repository.download(image, context: context)
            Issue.record("An idle provider was accepted as current")
        } catch {
            let failure = try #require(error as? BookOperationFailure)
            let boundary = BookOperationDiagnostics(operationID: context.operationID, bookID: manifest.id, phase: "edit")
            await repository.flushDiagnosticLogs()
            AppDiagnosticLogger(sink: sink).log(boundary.failureEntry("Library operation failed", error: failure, category: "library"))
        }
        let failures = sink.entries.filter { $0.level == .error }
        #expect(failures.count == 1)
        let failure = try #require(failures.first)
        #expect(failure.metadata["phase"] == .string("checkout_asset_download"))
        #expect(failure.metadata["operation_phase"] == .string("edit"))
        #expect(failure.metadata["chapter_id"] == .string(chapter.id.uuidString))
        #expect(failure.metadata["asset_index"] == .integer(4))
        #expect(failure.metadata["asset_key"] != nil)
        #expect(failure.metadata["file_size_bytes"] == .integer(1))
        #expect(failure.metadata["provider_is_uploaded"] == .bool(false))
        #expect(failure.error?.causes.last?.domain == "NSFileProviderErrorDomain")
        #expect(failure.error?.causes.last?.code == -1003)
        #expect(failure.message.contains("insufficient storage quota"))
        #expect(failure.message.contains("provider downloading: false"))
        #expect(!String(describing: sink.entries).contains("private-child-name"))
        #expect(!String(describing: sink.entries).contains("Private account"))
        #expect(!String(describing: sink.entries).contains(root.path))
    }

    @Test func staleDownloadedCopyRemainsProtectedUntilProviderReportsCurrent() async throws {
        let provider = LibraryDownloadProvider(readState: { _ in .init(isUbiquitousItem: true, status: "downloaded") },
                                              requestDownload: { _ in }, timeout: .zero)
        let repository = LibraryRepository(cacheRoot: .temporaryDirectory, downloadProvider: provider)
        await #expect(throws: BookOperationFailure.self) {
            try await repository.download(URL.temporaryDirectory.appendingPathComponent("stale-image.jpg"))
        }
    }

    @Test func originalProviderDownloadErrorAndCancellationArePreserved() async throws {
        let original = NSError(domain: "NSFileProviderErrorDomain", code: -1004,
                               userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)])
        let provider = LibraryDownloadProvider(readState: { _ in .init(isUbiquitousItem: true, status: "not_downloaded") },
                                              requestDownload: { _ in throw original })
        let repository = LibraryRepository(cacheRoot: .temporaryDirectory, downloadProvider: provider)
        do {
            try await repository.download(URL.temporaryDirectory.appendingPathComponent("image.jpg"))
            Issue.record("The provider failure was ignored")
        } catch {
            let failure = try #require(error as? BookOperationFailure)
            #expect(failure.underlyingLogError?.causes.map(\.code) == [-1004, NSURLErrorNotConnectedToInternet])
        }
        var cancelled = provider
        cancelled.requestDownload = { _ in throw CancellationError() }
        let cancelledRepository = LibraryRepository(cacheRoot: .temporaryDirectory, downloadProvider: cancelled)
        await #expect(throws: CancellationError.self) {
            try await cancelledRepository.download(URL.temporaryDirectory.appendingPathComponent("image.jpg"))
        }
    }
}
