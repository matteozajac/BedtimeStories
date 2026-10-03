import Foundation
import CoreData
import MZAppFoundation
import MZAppFoundationLocal
import Pulse
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct LoggingTests {
    @Test func traceAndWarningsRetainCallerSeverityAndSafeFields() throws {
        let sink = RecordingLogger()
        let previous = AppLog.logger
        AppLog.logger = sink
        defer { AppLog.logger = previous }
        let traceLine = #line + 1
        AppLog.trace("Connection attempt started", category: "connection", metadata: ["attempt": .integer(2), "authorization": .string("private credential")])
        let warningLine = #line + 1
        AppLog.warning("Connection will retry", error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "private endpoint"]), category: "connection")
        let trace = try #require(sink.entries.first)
        #expect(trace.level == .debug && trace.metadata["verbosity"] == .string("trace"))
        #expect(trace.metadata["attempt"] == .integer(2) && trace.metadata["authorization"] == nil)
        #expect(trace.source.line == traceLine && trace.source.file.hasSuffix("LoggingTests.swift"))
        let warning = try #require(sink.entries.last)
        #expect(warning.level == .warning && warning.source.line == warningLine)
        #expect(warning.error?.source == warning.source)
        #expect(warning.error?.causes.first?.code == NSURLErrorTimedOut)
        #expect(warning.error?.causes.first?.message == nil)
        #expect(warning.error?.stack.symbols.isEmpty == false)
    }

    @Test func wrappedFailureKeepsCapturedStackAcrossDelivery() throws {
        let sink = RecordingLogger()
        let frames = ["GeminiTransport.receive() frame with spaces", "NarrationTask.run() caller"]
        let captured = ErrorSnapshot(
            NSError(domain: "GeminiTransport", code: -57, userInfo: [NSLocalizedDescriptionKey: "private provider payload"]),
            stack: ErrorStack(origin: .supplied, symbols: frames),
            file: "Fixture/Connection.swift", function: "receive()", line: 41
        )
        sink.error("Connection failed", error: WrappedFailure(underlyingLogError: captured), category: "connection")
        let error = try #require(sink.entries.first?.error)
        #expect(error.causes.last?.domain == "GeminiTransport" && error.causes.last?.code == -57)
        #expect(error.stack.origin == .supplied && error.stack.symbols == frames)
        #expect(error.source == captured.source)
        #expect(!String(describing: error).contains("private provider payload"))
    }

    @Test func pulsePersistsConnectionTraceAndReadableErrorFramesOnce() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LoggerStore(storeURL: root, options: [.create, .synchronous])
        defer { try? store.destroy() }
        let pulse = PulseLogger(store: store)
        let configuration = AppConfiguration(bundleIdentifier: "com.example.logging", urlScheme: "fixture", environment: .internalTesting,
                                             preferences: .init(analytics: false, diagnostics: false))
        let engine = LocalTelemetryEngine(logger: pulse)
        let remote = RecordingDiagnosticsEngine(delivery: .remote)
        let services = AppServices(configuration: configuration,
                                   telemetry: Telemetry(configuration: configuration, schema: .init(events: [:]), diagnostics: [engine, remote]),
                                   logger: pulse, purchases: MockPurchases(),
                                   developerOptions: DeveloperOptions(configuration: configuration))
        services.logger.trace("Fixture connection started", category: "connection", metadata: ["phase": .string("request started")])
        let failure = ErrorSnapshot(NSError(domain: "GeminiTransport", code: -57),
                                    stack: .init(origin: .supplied, symbols: ["0 GeminiTransport receive frame with spaces"]),
                                    file: "Fixture/Gemini.swift", function: "receive()", line: 71)
        services.logger.error("Fixture connection failed", error: WrappedFailure(underlyingLogError: failure), category: "connection")
        #expect(!remote.enabled && remote.issues.isEmpty)
        let stored = try store.backgroundContext.performAndWait {
            let rows = try store.backgroundContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "LoggerMessageEntity"))
            var traceMetadata: String?
            var errorMetadata: [String] = []
            for row in rows {
                let text = row.value(forKey: "text") as? String
                if text == "Fixture connection started" { traceMetadata = row.value(forKey: "rawMetadata") as? String }
                if text == "Fixture connection failed", let fields = row.value(forKey: "rawMetadata") as? String {
                    errorMetadata.append(fields)
                }
            }
            return (traceMetadata, errorMetadata)
        }
        #expect(stored.0?.contains("verbosity: trace") == true)
        #expect(stored.0?.contains("phase: request started") == true)
        #expect(stored.1.count == 1)
        let metadata = try #require(stored.1.first)
        #expect(metadata.contains("error.stack: supplied"))
        #expect(metadata.contains("error.stack.00: 0 GeminiTransport receive frame with spaces"))
        #expect(metadata.contains("GeminiTransport") && metadata.contains("-57"))
    }

    @Test func cancelledTransportProducesTraceWithoutWarningOrError() {
        let sink = RecordingLogger()
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        sink.warning("Connection cancelled", error: cancelled, category: "connection")
        sink.error("Connection failed", error: cancelled, category: "connection")
        #expect(sink.entries.count == 1)
        #expect(sink.entries.first?.level == .debug && sink.entries.first?.error == nil)
        #expect(sink.entries.first?.metadata["cancelled"] == .bool(true))
    }

    @Test func corruptCachedCatalogLogsOriginalFailureBeforeFallback() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Cache")
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("private malformed catalog".utf8).write(to: cache.appendingPathComponent("catalog.json"))
        let sink = RecordingLogger()
        let repository = LibraryRepository(cacheRoot: cache, logDestination: FeatureLogDestination(logger: sink))
        let scan = try await repository.scan(root: library)
        await repository.flushDiagnosticLogs()
        #expect(scan.books.isEmpty)
        let warnings = sink.entries.filter { $0.level == .warning }
        #expect(warnings.count == 1)
        let entry = try #require(warnings.first)
        #expect(entry.message == "Cached library catalog unavailable")
        #expect(entry.error?.causes.first?.type.contains("DecodingError") == true)
        #expect(entry.error?.stack.symbols.isEmpty == false)
        #expect(entry.error?.source == entry.source)
        #expect(!String(describing: sink.entries).contains("private malformed catalog"))
        #expect(!String(describing: sink.entries).contains(root.path))
    }

    @Test func existingDraftCorruptionIsLoggedDuringSuccessfulRecovery() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sink = RecordingLogger()
        let store = BookDraftStore(root: root, logDestination: FeatureLogDestination(logger: sink))
        let draft = try await store.create()
        try Data("private malformed draft".utf8).write(to: root.appendingPathComponent(draft.id.uuidString).appendingPathComponent("draft.json"))
        try await store.save(draft)
        await store.flushDiagnosticLogs()
        #expect(try await store.load(draft.id) == draft)
        let warnings = sink.entries.filter { $0.level == .warning }
        #expect(warnings.count == 1)
        #expect(warnings.first?.error?.causes.first?.type.contains("DecodingError") == true)
        #expect(warnings.first?.source.file.hasSuffix("BookDraftStore.swift") == true)
        #expect(!String(describing: sink.entries).contains("private malformed draft"))
    }

    @Test func cloudPresentationWrapperPreservesEvidenceAndAvoidsViewDuplicates() throws {
        let sink = RecordingLogger()
        let previous = AppLog.logger
        AppLog.logger = sink
        defer { AppLog.logger = previous }
        let snapshot = ErrorSnapshot(NSError(domain: "FirebaseFunctions", code: 14, userInfo: [NSLocalizedDescriptionKey: "private provider response"]),
                                     file: "Fixture/Cloud.swift", function: "dispatch()", line: 28)
        let presentation = CloudNarrationFailure.retryLater
        let context = CloudNarrationFailureContext(presentation: presentation, underlyingLogError: snapshot)
        CloudNarrationDiagnostics.reportIfNeeded("Cloud operation failed", error: context)
        let reported = CloudNarrationReportedFailure(presentation: presentation, underlyingLogError: snapshot)
        CloudNarrationDiagnostics.reportIfNeeded("View operation failed", error: reported)
        #expect(sink.entries.count == 1)
        #expect(sink.entries.first?.error?.causes.last?.domain == "FirebaseFunctions")
        #expect(sink.entries.first?.error?.stack == snapshot.stack)
        #expect(reported.localizedDescription == presentation.localizedDescription)
        #expect(!String(describing: sink.entries).contains("private provider response"))
    }

    @Test func cloudTaskCorrelationMatchesBackendAndRejectsPrivateStatusText() {
        #expect(CloudNarrationDiagnostics.taskKey(kind: "narrate", uid: "fixture-owner", id: "fixture-job") == "65a428a6d734ca5ef65418fd5c07952d400048948e0f60187d1e3a5dc0f6dde5")
        #expect(CloudNarrationDiagnostics.taskKey(kind: "enroll", uid: "fixture-owner", id: "fixture-voice") == "7277d23edbf7ad711d3c948f6b9fdee08dfb8594b12df7020c77a45a64a56b53")
        #expect(CloudNarrationBackendFailure.safeCode("provider_quota") == "provider_quota")
        #expect(CloudNarrationBackendFailure.safeCode("private child name or provider body") == "unknown_backend_failure")
        #expect(CloudNarrationBackendFailure.safeCode(nil) == "unknown_backend_failure")
    }

    @Test func facadeRetainsOriginalErrorAndCallerWithoutPrivateText() throws {
        let sink = RecordingLogger()
        let previous = AppLog.logger
        AppLog.logger = sink
        defer { AppLog.logger = previous }
        let underlying = NSError(domain: "AudioDecoder", code: -17, userInfo: [NSLocalizedDescriptionKey: "private recording"])
        let failure = NSError(domain: "StoryOperation", code: -42, userInfo: [
            NSLocalizedDescriptionKey: "private story title and /Users/private/book",
            NSUnderlyingErrorKey: underlying
        ])
        let line = #line + 1
        AppLog.error("Fixture operation failed", error: failure, category: "fixture", metadata: ["phase": .string("decode"), "prompt": .string("private story idea")])
        let entries = sink.entries.filter { $0.message == "Fixture operation failed" }
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        let snapshot = try #require(entry.error)
        #expect(snapshot.causes.map(\.domain) == ["StoryOperation", "AudioDecoder"])
        #expect(snapshot.causes.map(\.code) == [-42, -17])
        #expect(snapshot.causes.allSatisfy { $0.message == nil })
        #expect(snapshot.stack.origin == .reporting && !snapshot.stack.symbols.isEmpty)
        #expect(entry.source.file.hasSuffix("LoggingTests.swift") && entry.source.line == line)
        #expect(snapshot.source == entry.source)
        #expect(entry.metadata == ["phase": .string("decode")])
    }

    @Test func generationFailureLogsUnderlyingErrorOnceWithoutStoryContent() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sink = RecordingLogger()
        let generator = FailingGenerator(failure: NSError(domain: "ModelTransport", code: -901, userInfo: [NSLocalizedDescriptionKey: "private model response"]))
        let model = StoryGenerationModel(store: BookDraftStore(root: root), generator: generator, logger: sink)
        await model.generate(request(), mode: .onDevice)
        let errors = sink.entries.filter { $0.level == .error }
        #expect(errors.count == 1)
        let entry = try #require(errors.first)
        #expect(entry.error?.causes.first?.domain == "ModelTransport")
        #expect(entry.error?.causes.first?.code == -901)
        #expect(entry.error?.causes.first?.message == nil)
        #expect(entry.source.file.hasSuffix("StoryGenerationModel.swift"))
        #expect(!String(describing: sink.entries).contains("private story idea"))
        #expect(!String(describing: sink.entries).contains("private model response"))
        #expect(model.draft == nil && !model.completed)
    }

    @Test func cancellationDoesNotBecomeAnError() async {
        let sink = RecordingLogger()
        let model = StoryGenerationModel(store: BookDraftStore(root: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                                         generator: FailingGenerator(failure: CancellationError()), logger: sink)
        await model.generate(request(), mode: .onDevice)
        #expect(sink.entries.allSatisfy { $0.level != .error })
    }

    #if MZ_LOCAL
    @Test func localCloudAdapterCannotInitializeProvidersOrGrantAccess() async throws {
        let model = CloudNarrationModel()
        #expect(!model.isConfigured && !model.isEnabled && model.userID == nil)
        #expect(model.voices.isEmpty && model.jobs.isEmpty)
        await #expect(throws: CloudNarrationFailure.unavailable) { try await model.deleteAccount() }
        await #expect(throws: CloudNarrationFailure.unavailable) { try await model.startVoicePreview(profileID: "fixture") }
    }
    #endif

    private func request() -> StoryGenerationRequest {
        .init(description: "private story idea", language: .english, readerAge: .preschool, readingMinutes: 1, wordsPerMinute: 140)
    }

    private final class FailingGenerator: StoryGenerating {
        let failure: any Error
        init(failure: any Error) { self.failure = failure }
        func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String? { nil }
        func book(for request: StoryGenerationRequest, mode: StoryGenerationMode) async throws -> GeneratedStoryBook { throw failure }
    }

    private struct WrappedFailure: Error, UnderlyingErrorSnapshotProviding {
        let underlyingLogError: ErrorSnapshot?
    }
}
