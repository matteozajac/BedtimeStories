import Foundation
import MZAppFoundation
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct LoggingTests {
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
}
