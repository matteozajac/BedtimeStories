import Foundation
import FoundationModels
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct StoryGenerationTests {
    @Test func generatedDraftSurvivesRelaunchAndUsesExistingBookFormat() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        let generator = TestGenerator()
        let model = StoryGenerationModel(store: store, generator: generator)
        await model.generate(request(), mode: .onDevice)
        #expect(model.completed && !model.working && model.message == nil)
        let draft = try #require(model.draft)
        let recovered = try await BookDraftStore(root: store.root).load(draft.id)
        #expect(recovered == draft)
        #expect(recovered.chapters.map(\.text) == ["The fox found a star.", "The fox came home and slept."])
        #expect(generator.continuityReceived == ["", "The fox found a star."])
        #expect(generator.modes == [.onDevice, .onDevice, .onDevice])
        #expect(draft.cover == nil && draft.author.isEmpty && draft.mediaPaths.isEmpty)
        let staged = try await store.stageBook(draft)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let manifest = try BookManifest.load(from: staged.folder, requireAssets: true)
        #expect(manifest.hasReading && !manifest.hasAudio)
        #expect(manifest.orderedChapters.map(\.id) == draft.chapters.map(\.id))
        let repository = LibraryRepository(cacheRoot: root.appendingPathComponent("Cache"))
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try await repository.commitImport(staged, root: library, replacing: false)
        let book = try #require(try await repository.scan(root: library).books.first)
        let export = try await repository.share(book, root: library)
        defer { try? FileManager.default.removeItem(at: export) }
        let imported = try await repository.stageImport(export)
        #expect(imported.manifest == manifest)
        await repository.discardImport(imported)
    }

    @Test func cloudQuotaFailurePreservesChaptersWithoutChangingProcessingMode() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator()
        generator.secondChapterError = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(.init(debugDescription: "private backend detail"))
        let store = BookDraftStore(root: root)
        let model = StoryGenerationModel(store: store, generator: generator)
        await model.generate(request(), mode: .privateCloud)
        #expect(!model.completed && !model.working && model.completedChapterCount == 1)
        #expect(model.message == StoryGenerationFailure.cloudQuota.errorDescription)
        #expect(model.message?.contains("private backend detail") == false)
        let draft = try #require(model.draft)
        #expect(try await store.load(draft.id) == draft)
        #expect(draft.chapters[0].text == "The fox found a star.")
        #expect(draft.chapters[1].text.isEmpty)
        #expect(generator.modes.allSatisfy { $0 == .privateCloud })
    }

    @Test func cancellationPreservesCompletedChapterAndAllowsAnotherDraft() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator()
        generator.pauseSecondChapter = true
        let store = BookDraftStore(root: root)
        let model = StoryGenerationModel(store: store, generator: generator)
        let task = Task { await model.generate(request(), mode: .onDevice) }
        await generator.waitForSecondChapter()
        task.cancel()
        await task.value
        #expect(!model.working && !model.completed && model.completedChapterCount == 1)
        let first = try #require(model.draft)
        #expect(try await store.load(first.id).chapters[0].text == "The fox found a star.")
        generator.pauseSecondChapter = false
        await model.generate(request(), mode: .onDevice)
        #expect(model.completed)
        #expect(model.draft?.id != first.id)
        #expect(try await store.list().count == 2)
        #expect(try await store.load(first.id) == first)
    }

    @Test func invalidBriefUnavailableModelAndInvalidOutlineDoNotCreateDrafts() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        let generator = TestGenerator()
        let model = StoryGenerationModel(store: store, generator: generator)
        await model.generate(request(description: " \n "), mode: .onDevice)
        #expect(generator.modes.isEmpty && model.draft == nil)
        await model.generate(request(description: String(repeating: "a", count: 601)), mode: .onDevice)
        #expect(generator.modes.isEmpty)
        generator.unavailable = "Model is downloading."
        await model.generate(request(), mode: .onDevice)
        #expect(model.message == "Model is downloading." && generator.modes.isEmpty)
        generator.unavailable = nil
        generator.invalidPlan = true
        await model.generate(request(), mode: .onDevice)
        #expect(model.draft == nil && model.message == StoryGenerationFailure.invalidResponse.errorDescription)
        #expect(try await store.list().isEmpty)
    }

    @Test func failedSaveDoesNotReportUnsavedDraftAsRecoverable() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocked".utf8).write(to: root)
        let model = StoryGenerationModel(store: BookDraftStore(root: root), generator: TestGenerator())
        await model.generate(request(), mode: .onDevice)
        #expect(model.draft == nil && model.completedChapterCount == 0 && !model.completed)
        #expect(model.message == StoryGenerationFailure.saveFailed.errorDescription)
    }

    @Test func invalidChapterAndSafetyRefusalKeepPreviousContent() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator()
        generator.invalidChapter = true
        let store = BookDraftStore(root: root)
        let model = StoryGenerationModel(store: store, generator: generator)
        await model.generate(request(), mode: .onDevice)
        #expect(model.completedChapterCount == 1 && !model.completed)
        let first = try #require(model.draft)
        #expect(try await store.load(first.id).chapters[1].text.isEmpty)
        generator.invalidChapter = false
        generator.secondChapterError = LanguageModelError.guardrailViolation(.init(debugDescription: "do not expose the prompt"))
        await model.generate(request(), mode: .onDevice)
        #expect(model.message == StoryGenerationFailure.refused.errorDescription)
        #expect(model.message?.contains("do not expose") == false)
        #expect(try await store.load(first.id) == first)
    }

    @Test func defaultCloudBuildCannotSendRequests() {
        #if !BEDTIME_PRIVATE_CLOUD_COMPUTE
        let generator = FoundationStoryGenerator()
        #expect(!FoundationStoryGenerator.cloudEnabled)
        #expect(generator.unavailabilityReason(for: .privateCloud, language: .english) != nil)
        #endif
    }

    private func request(description: String = "A fox follows a star home.") -> StoryGenerationRequest {
        StoryGenerationRequest(description: description, language: .english, readerAge: .preschool, chapterCount: 2)
    }

    private func workspace() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StoryGenerationTests-\(UUID().uuidString)")
    }

    @MainActor
    private final class TestGenerator: StoryGenerating {
        var modes: [StoryGenerationMode] = []
        var continuityReceived: [String] = []
        var secondChapterError: Error?
        var unavailable: String?
        var invalidPlan = false
        var invalidChapter = false
        var pauseSecondChapter = false
        private var secondChapterStarted = false
        private var waiter: CheckedContinuation<Void, Never>?

        func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String? { unavailable }

        func plan(for request: StoryGenerationRequest, mode: StoryGenerationMode) async throws -> GeneratedStoryPlan {
            modes.append(mode)
            return GeneratedStoryPlan(title: invalidPlan ? "" : "The Fox and the Star", summary: "A fox finds the way home.", characters: "A kind, sleepy fox.", chapters: [GeneratedChapterPlan(title: "A Star", plot: "Find the star."), GeneratedChapterPlan(title: "Home", plot: "Get home and fall asleep.")])
        }

        func chapter(for request: StoryGenerationRequest, plan: GeneratedStoryPlan, index: Int, continuity: String, mode: StoryGenerationMode) async throws -> GeneratedStoryChapter {
            modes.append(mode)
            continuityReceived.append(continuity)
            if index == 1 {
                secondChapterStarted = true
                waiter?.resume(); waiter = nil
                if pauseSecondChapter { try await Task.sleep(for: .seconds(30)) }
                if let secondChapterError { throw secondChapterError }
                if invalidChapter { return GeneratedStoryChapter(text: " \n ", continuity: "") }
            }
            return GeneratedStoryChapter(text: index == 0 ? "The fox found a star." : "The fox came home and slept.", continuity: "The fox found a star.")
        }

        func waitForSecondChapter() async {
            if secondChapterStarted { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }
}
