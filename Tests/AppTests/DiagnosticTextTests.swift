import CoreData
import Foundation
import MZAppFoundation
import MZAppFoundationLocal
import Pulse
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct DiagnosticTextTests {
    @Test func normalPulseCopyContainsContextCausesAndOriginalStackWithoutPrivateDescriptions() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LoggerStore(storeURL: root, options: [.create, .synchronous])
        defer { try? store.destroy() }
        let pulse = AppPulseLogger(store: store)
        let logger = AppDiagnosticLogger(sink: pulse)
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 20,
                                 userInfo: [NSLocalizedDescriptionKey: "private story and /Users/private/story"])
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                            userInfo: [NSUnderlyingErrorKey: underlying,
                                       NSLocalizedDescriptionKey: "secret provider response https://private.invalid"])
        let snapshot = ErrorSnapshot(error,
                                     stack: .init(origin: .supplied, symbols: ["BookCheckout.download() original frame"]),
                                     file: "Library/Checkout.swift", function: "download()", line: 52)
        logger.log(LogEntry("Book editing checkout failed", level: .error, category: "library",
                            metadata: ["operation_id": .string("fixture-operation"), "phase": .string("download_audio"),
                                       "asset_index": .integer(3), "authorization": .string("private bearer token")],
                            error: snapshot, file: "Library/Model.swift", function: "editBook()", line: 91))
        await pulse.flush()
        let records = try store.backgroundContext.performAndWait {
            try store.backgroundContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "LoggerMessageEntity"))
                .map { ($0.value(forKey: "text") as? String ?? "", $0.value(forKey: "rawMetadata") as? String ?? "") }
        }
        #expect(records.count == 1)
        let record = try #require(records.first)
        // Pulse's built-in text export renders precisely this message.text value.
        #expect(record.0.contains("phase=download_audio") && record.0.contains("asset_index=3"))
        #expect(record.0.contains("operation_id=fixture-operation"))
        #expect(record.0.contains("NSCocoaErrorDomain (257)"))
        #expect(record.0.contains("access was denied"))
        #expect(record.0.contains("NSPOSIXErrorDomain (20)"))
        #expect(record.0.contains("A required directory is a regular file"))
        #expect(record.0.contains("Source: Library/Model.swift:91"))
        #expect(record.0.contains("Captured: Library/Checkout.swift:52"))
        #expect(record.0.contains("Stack (supplied):\nBookCheckout.download() original frame"))
        #expect(record.1.contains("error.stack.00: BookCheckout.download() original frame"))
        #expect(!record.0.contains("private story") && !record.0.contains("secret provider response"))
        #expect(!record.0.contains("private.invalid") && !record.0.contains("authorization"))
    }

    @Test(.timeLimit(.minutes(1))) func loggingErrorsWhileTheConsoleObservesSavesDoesNotBlockTheMainActor() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LoggerStore(storeURL: root, options: [.create])
        defer { try? store.destroy() }
        let request = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: store.viewContext,
                                                   sectionNameKeyPath: nil, cacheName: nil)
        let observer = DiagnosticResultsObserver()
        controller.delegate = observer
        try controller.performFetch()
        let pulse = AppPulseLogger(store: store)
        let logger = AppDiagnosticLogger(sink: pulse)
        for index in 0..<20 {
            logger.error("Observed connection failed", error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
                         category: "connection", metadata: ["attempt": .integer(index), "phase": .string("response decoding")])
            await pulse.flush()
        }
        let fields = try await store.backgroundContext.perform {
            try store.backgroundContext.fetch(NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity"))
                .map { $0.rawMetadata ?? "" }
        }
        #expect(fields.count == 20)
        #expect(fields.allSatisfy { $0.contains("phase: response decoding") && $0.contains("error.stack.00:") && !$0.contains("mz_record_id:") })
        #expect(controller.fetchedObjects?.count == 20)
        _ = observer // Retain the fetched-results observer throughout all saves.
    }

    @Test func structuredDiagnosticsKeepOriginalMessageAndRouteExactlyOnce() throws {
        let sink = RecordingLogger()
        let readable = AppDiagnosticLogger(sink: sink)
        let local = LocalTelemetryEngine(logger: readable)
        // Simulator runtime safety blocks remote engines even with consent.
        // A recording diagnostics engine verifies the original routed payload.
        let diagnostics = RecordingDiagnosticsEngine(delivery: .local)
        let configuration = AppConfiguration(bundleIdentifier: "com.example.diagnostic-copy", urlScheme: "fixture",
                                             environment: .internalTesting,
                                             preferences: .init(analytics: false, diagnostics: true))
        let services = AppServices(configuration: configuration,
                                   telemetry: Telemetry(configuration: configuration, schema: .init(events: [:]),
                                                        diagnostics: [local, diagnostics]),
                                   logger: readable, purchases: MockPurchases(),
                                   developerOptions: DeveloperOptions(configuration: configuration))
        let snapshot = ErrorSnapshot(NSError(domain: "UnknownProvider", code: -57),
                                     stack: .init(origin: .supplied, symbols: ["original provider frame"]))
        services.logger.log(LogEntry("Fixture request failed", level: .error, category: "connection",
                                     metadata: ["phase": .string("decode")], error: snapshot))
        #expect(sink.entries.count == 1 && diagnostics.issues.count == 1)
        #expect(diagnostics.issues.first?.code == "Fixture request failed")
        #expect(diagnostics.issues.first?.error == snapshot)
        #expect(sink.entries.first?.message.contains("UnknownProvider (-57)") == true)
        #expect(sink.entries.first?.message.contains("Stack (supplied)") == true)
        #expect(sink.entries.first?.error == snapshot)
    }

    @Test func traceFieldsAndAuditedAppErrorMessagesAreReadable() throws {
        let sink = RecordingLogger()
        let readable = AppDiagnosticLogger(sink: sink)
        readable.trace("Book checkout asset download started", category: "library",
                       metadata: ["asset_kind": .string("audio"), "elapsed_ms": .integer(120),
                                  "prompt": .string("private prompt")])
        readable.error("Book checkout failed", error: SafeCheckoutFailure(), category: "library")
        #expect(sink.entries.first?.message.contains("asset_kind=audio") == true)
        #expect(sink.entries.first?.message.contains("elapsed_ms=120") == true)
        #expect(sink.entries.last?.message.contains("iCloud asset download timed out during book checkout.") == true)
        #expect(sink.entries.last?.message.contains("Stack (reporting)") == true)
        #expect(!String(describing: sink.entries).contains("private prompt"))
    }

    @Test func readableLocalErrorsRespectRemoteDiagnosticsOptOut() {
        let sink = RecordingLogger()
        let readable = AppDiagnosticLogger(sink: sink)
        let remote = RecordingDiagnosticsEngine(delivery: .remote)
        let configuration = AppConfiguration(bundleIdentifier: "com.example.local-copy", urlScheme: "fixture",
                                             environment: .internalTesting,
                                             preferences: .init(analytics: false, diagnostics: false))
        let services = AppServices(configuration: configuration,
                                   telemetry: Telemetry(configuration: configuration, schema: .init(events: [:]),
                                                        diagnostics: [LocalTelemetryEngine(logger: readable), remote]),
                                   logger: readable, purchases: MockPurchases(),
                                   developerOptions: DeveloperOptions(configuration: configuration))
        services.logger.error("Offline request failed", error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), category: "connection")
        #expect(sink.entries.count == 1 && !remote.enabled && remote.issues.isEmpty)
        #expect(sink.entries.first?.message.contains("The device is offline.") == true)
        #expect(sink.entries.first?.message.contains("Stack (reporting)") == true)
    }

    @Test func bookCheckoutTimelineCorrelatesAssetsAndPreservesPrivateBookContents() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("Library")
        let folder = library.appendingPathComponent("PrivateBook")
        let manifest = BookManifest(title: "private book title", chapters: [BookChapter(text: "chapters/private-name.md")])
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("chapters"), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("book.json"))
        try Data("private story contents".utf8).write(to: folder.appendingPathComponent("chapters/private-name.md"))
        let sink = RecordingLogger()
        let repository = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"), logDestination: FeatureLogDestination(logger: sink))
        let checkout = try await repository.checkout(LibraryBook(manifest: manifest, folder: folder), root: library, operationID: "fixture-checkout")
        await repository.flushDiagnosticLogs()
        let entries = sink.entries.filter { $0.metadata["operation_id"] == .string("fixture-checkout") }
        #expect(entries.first?.message == "Book edit checkout started")
        #expect(entries.last?.message == "Book edit checkout completed")
        #expect(entries.contains { $0.metadata["asset_kind"] == .string("text") && $0.metadata["asset_index"] == .integer(1) })
        #expect(entries.contains { $0.message == "File provider read coordination requested" })
        #expect(entries.contains { $0.message == "File provider read access granted" })
        #expect(entries.allSatisfy { $0.metadata["book_id"] == .string(manifest.id.uuidString) && $0.metadata["elapsed_ms"] != nil })
        #expect(!String(describing: entries).contains("private book title"))
        #expect(!String(describing: entries).contains("private-name.md"))
        #expect(!String(describing: entries).contains("private story contents"))
        #expect(!String(describing: entries).contains(root.path))
        await repository.discardImport(checkout.book)
    }

    @Test func failedCheckoutCopyIdentifiesFailedPhaseAndOriginalDecodingError() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("Library")
        let folder = library.appendingPathComponent("PrivateBook")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("private corrupted manifest".utf8).write(to: folder.appendingPathComponent("book.json"))
        let sink = RecordingLogger()
        let repository = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"), logDestination: FeatureLogDestination(logger: sink))
        do {
            _ = try await repository.checkout(LibraryBook(manifest: BookManifest(title: "private title"), folder: folder), root: library, operationID: "failed-checkout")
            Issue.record("A malformed manifest was accepted for editing")
        } catch {
            let preserved = try #require(error as? BookOperationFailure)
            #expect(preserved.phase == "checkout_manifest_read" && preserved.operationID == "failed-checkout")
            let entry = LogEntry("Book editing checkout failed", level: .error, category: "library", error: ErrorSnapshot(preserved))
            await repository.flushDiagnosticLogs()
            AppDiagnosticLogger(sink: sink).log(entry)
        }
        await repository.flushDiagnosticLogs()
        #expect(sink.entries.last?.level == .error)
        let errors = sink.entries.filter { $0.level == .error }
        #expect(errors.count == 1)
        let entry = try #require(errors.first)
        #expect(entry.message.contains("checkout_manifest_read"))
        #expect(entry.message.contains("failed-checkout"))
        #expect(entry.error?.causes.contains { $0.type.contains("DecodingError") } == true)
        #expect(entry.message.contains("Stack (reporting)"))
        #expect(!String(describing: sink.entries).contains("private corrupted manifest"))
        #expect(!String(describing: sink.entries).contains(root.path))
    }

    @Test func GeminiWorkerFailureExplainsKnownCodeAndNeverCopiesUnknownProviderText() {
        let sink = RecordingLogger()
        let readable = AppDiagnosticLogger(sink: sink)
        readable.error("Book narration worker failed", error: CloudNarrationBackendFailure(code: "provider_quota"), category: "cloud_narration",
                       metadata: ["backend_error_code": .string("provider_quota"), "task_key": .string("fixture-task-key")])
        #expect(sink.entries.first?.message.contains("Gemini provider quota or billing limits prevented completion") == true)
        #expect(sink.entries.first?.message.contains("backend_error_code=provider_quota") == true)
        let unknown = CloudNarrationBackendFailure(code: "private provider response with user text")
        #expect(unknown.code == "unknown_backend_failure")
        readable.error("Book narration worker failed", error: unknown, category: "cloud_narration")
        #expect(sink.entries.last?.message.contains("Correlate the task key with worker logs") == true)
        #expect(!String(describing: sink.entries).contains("private provider response with user text"))
    }

    private struct SafeCheckoutFailure: Error, LoggableError {
        var logMessage: String { "iCloud asset download timed out during book checkout." }
    }
}

private final class DiagnosticResultsObserver: NSObject, NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) { }
}
