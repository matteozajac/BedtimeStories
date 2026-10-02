import Foundation
import FoundationModels
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct StoryGenerationTests {
    @Test func completeBookIsGeneratedOnceValidatedSavedAndExported() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root.appendingPathComponent("Drafts"))
        let generator = TestGenerator()
        let model = StoryGenerationModel(store: store, generator: generator)
        await model.generate(request(), mode: .onDevice)
        #expect(model.completed && !model.working && model.message == nil)
        #expect(generator.modes == [.onDevice])
        let draft = try #require(model.draft)
        #expect(draft.chapters.count == 2 && model.completedChapterCount == 2)
        #expect(draft.chapters.map(\.text) == TestGenerator.validBook.chapters.map(\.text))
        #expect(try await BookDraftStore(root: store.root).load(draft.id) == draft)
        let staged = try await store.stageBook(draft)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let manifest = try BookManifest.load(from: staged.folder, requireAssets: true)
        #expect(manifest.hasReading && !manifest.hasAudio)
        #expect(manifest.orderedChapters.allSatisfy { $0.text != nil })
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

    @Test func emptyGeneratedTextIsRecoveredBeforeReportingSuccess() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator()
        generator.emptyOnce = true
        let model = StoryGenerationModel(store: BookDraftStore(root: root), generator: generator)
        await model.generate(request(), mode: .onDevice)
        #expect(model.completed && model.message == nil)
        #expect(generator.modes == [.onDevice, .onDevice])
        #expect(model.draft?.chapters.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true)
        #expect(try await model.store.list().count == 1)
    }

    @Test func validatorRejectsMissingShortDuplicateAndUnfinishedContent() throws {
        let valid = TestGenerator.validBook
        var invalidBooks: [GeneratedStoryBook] = []
        for body in ["", " \n ", "\u{200B}\u{FEFF}", "A title only.", String(repeating: "... ", count: 80), String(valid.chapters[0].text.dropLast())] {
            var invalid = valid; invalid.chapters[0].text = body; invalidBooks.append(invalid)
        }
        var missing = valid; missing.chapters.removeLast(); invalidBooks.append(missing)
        var duplicate = valid; duplicate.chapters[1] = duplicate.chapters[0]; invalidBooks.append(duplicate)
        var noTitle = valid; noTitle.title = " \n "; invalidBooks.append(noTitle)
        for invalid in invalidBooks {
            #expect(throws: StoryGenerationFailure.self) { try StoryOutputValidator.validate(invalid, request: request()) }
        }
        var padded = valid; padded.title = " \u{FEFF}The Fox and the Star \n"
        #expect(try StoryOutputValidator.validate(padded, request: request()).title == "The Fox and the Star")
    }

    @Test func repeatedInvalidResponseNeverSavesAnEmptyOrPartialBook() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator(); generator.invalidAlways = true
        let model = StoryGenerationModel(store: BookDraftStore(root: root), generator: generator)
        await model.generate(request(), mode: .onDevice)
        #expect(!model.completed && model.draft == nil && model.completedChapterCount == 0)
        #expect(generator.modes.count == 2)
        #expect(model.message == StoryGenerationFailure.invalidResponse.errorDescription)
        #expect(try await model.store.list().isEmpty)
    }

    @Test func durationRetryIncludesMeasuredLengthAndKeepsWholeBrief() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator(); generator.tooLongOnce = true
        let model = StoryGenerationModel(store: BookDraftStore(root: root), generator: generator)
        let original = request()
        await model.generate(original, mode: .onDevice)
        #expect(model.completed && generator.requests.count == 2)
        let retry = try #require(generator.requests.last)
        #expect(retry.description == original.description && retry.targetWords == original.targetWords)
        #expect(retry.previousWordCount == 2 * StoryReadingLength.wordCount(TestGenerator.validBook.chapters.map(\.text).joined(separator: " ")))
        #expect(try retry.prompt.contains("rejected as too long"))
        #expect(try await model.store.list().count == 1)
    }

    @Test func refusalAndCloudQuotaDoNotRetryAndPreservePreviousDrafts() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        let previous = try await store.create()
        let generator = TestGenerator()
        generator.failure = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(.init(debugDescription: "private backend detail"))
        let model = StoryGenerationModel(store: store, generator: generator)
        await model.generate(request(), mode: .privateCloud)
        #expect(model.message == StoryGenerationFailure.cloudQuota.errorDescription)
        #expect(generator.modes == [.privateCloud] && model.draft == nil)
        #expect(try await store.load(previous.id) == previous)
        generator.failure = LanguageModelError.guardrailViolation(.init(debugDescription: "do not expose the prompt"))
        await model.generate(request(), mode: .onDevice)
        #expect(model.message == StoryGenerationFailure.refused.errorDescription)
        #expect(generator.modes == [.privateCloud, .onDevice])
        #expect(try await store.list().count == 1)
    }

    @Test func cancellationSavesNoOutlineAndAnotherAttemptKeepsExistingDrafts() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookDraftStore(root: root)
        let previous = try await store.create()
        let generator = TestGenerator(); generator.pause = true
        let model = StoryGenerationModel(store: store, generator: generator)
        let task = Task { await model.generate(request(), mode: .onDevice) }
        await generator.waitForRequest()
        task.cancel(); await task.value
        #expect(!model.working && !model.completed && model.draft == nil)
        #expect(try await store.list().count == 1)
        generator.pause = false
        await model.generate(request(), mode: .onDevice)
        #expect(model.completed)
        #expect(try await store.list().count == 2)
        #expect(try await store.load(previous.id) == previous)
    }

    @Test func invalidInputUnavailableModelAndFailedSaveCreateNoRecoverableDraft() async throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = TestGenerator()
        let model = StoryGenerationModel(store: BookDraftStore(root: root), generator: generator)
        for description in [" \n ", String(repeating: "a", count: 601)] {
            await model.generate(request(description: description), mode: .onDevice)
            #expect(generator.modes.isEmpty && model.draft == nil)
        }
        generator.unavailable = "Model is downloading."
        await model.generate(request(), mode: .onDevice)
        #expect(model.message == "Model is downloading." && generator.modes.isEmpty)
        generator.unavailable = nil
        try Data("blocked".utf8).write(to: root)
        await model.generate(request(), mode: .onDevice)
        #expect(model.draft == nil && !model.completed)
        #expect(model.message == StoryGenerationFailure.saveFailed.errorDescription)
        #expect(generator.modes.count == 1)
    }

    @Test func buildConfigurationMatchesCloudGate() {
        #if BEDTIME_PRIVATE_CLOUD_COMPUTE
        #expect(FoundationStoryGenerator.cloudEnabled)
        #else
        let generator = FoundationStoryGenerator()
        #expect(!FoundationStoryGenerator.cloudEnabled)
        #expect(generator.unavailabilityReason(for: .privateCloud, language: .english) != nil)
        #endif
    }

    @Test func twentyMinuteTargetAppliesToTotalWordsAcrossAnyChapterCount() throws {
        let requested = StoryGenerationRequest(description: "A fox goes home.", language: .english, readerAge: .preschool, readingMinutes: 20, wordsPerMinute: 120)
        #expect(requested.targetWords == 2_400)
        let short = StoryGenerationRequest(description: "A fox goes home.", language: .english, readerAge: .preschool, readingMinutes: 2, wordsPerMinute: 120)
        #expect(short.maximumChapters == 2)
        _ = try GeneratedStoryBook.schema(for: short)
        _ = try GeneratedStoryBook.schema(for: requested)
        #expect(throws: StoryGenerationFailure.self) { try requested.validate(mode: .onDevice) }
        try requested.validate(mode: .privateCloud)
        let sentence = "The little fox walked home beneath the soft moonlight. "
        let one = GeneratedStoryBook(title: "Home", summary: "A fox goes home.", chapters: [GeneratedBookChapter(title: "Homeward", text: String(repeating: sentence, count: 240))])
        #expect(try StoryOutputValidator.validate(one, request: requested).chapters.count == 1)
        let five = GeneratedStoryBook(title: "Home", summary: "A fox goes home.", chapters: (1...5).map { GeneratedBookChapter(title: "Part \($0)", text: "Scene \($0). " + String(repeating: sentence, count: 48)) })
        #expect(try StoryOutputValidator.validate(five, request: requested).chapters.count == 5)
        #expect(throws: StoryGenerationFailure.self) { try StoryOutputValidator.validate(TestGenerator.validBook, request: requested) }
        #expect(try requested.prompt.contains("entire book") && requested.prompt.contains("2400"))
    }

    @Test func illustrationContextUsesSharedAppearanceAndCurrentChapter() {
        var draft = BookDraft(); draft.title = "Milo"; draft.summary = "A fox meets an owl."
        draft.illustrationGuide = "Milo is a little red fox wearing a blue scarf."
        draft.chapters[0].text = "Milo meets an owl beside a stream."
        draft.chapters.append(DraftChapter(title: "Home", text: "Milo rests beside the window."))
        #expect(IllustrationPromptBuilder.sharedGuide(draft).contains("blue scarf"))
        #expect(IllustrationPromptBuilder.context(draft, chapterID: draft.chapters[1].id).contains("window"))
        #expect(!IllustrationPromptBuilder.context(draft, chapterID: draft.chapters[1].id).contains("stream"))
        #expect(IllustrationPromptBuilder.style.contains("storybook"))
    }

    private func request(description: String = "A fox follows a star home.") -> StoryGenerationRequest {
        StoryGenerationRequest(description: description, language: .english, readerAge: .preschool, readingMinutes: 1, wordsPerMinute: 140)
    }
    private func workspace() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StoryGenerationTests-\(UUID().uuidString)")
    }

    @MainActor private final class TestGenerator: StoryGenerating {
        static var validBook: GeneratedStoryBook {
            let opening = "A sleepy fox walked beside a quiet stream. The moon shone above the trees, and a little star glimmered in the soft water. He followed its gentle light along the familiar path. A friendly owl showed him the way past a field of flowers. The fox thanked his friend and listened to the peaceful night. Soon he could see the warm window of his home shining between the trees."
            let ending = "At home, the little fox found his family waiting beside the glowing window. He told them about the star and his kind friend in the forest. They shared a warm drink and watched the moon together. Then the fox curled up beneath a soft blanket. He knew the path would always lead him home. His family wished him sweet dreams, and the fox closed his eyes as the stars twinkled quietly above."
            return GeneratedStoryBook(title: "The Fox and the Star", summary: "A fox follows a star home.", chapters: [GeneratedBookChapter(title: "The Star", text: opening), GeneratedBookChapter(title: "Home", text: ending)])
        }
        var modes: [StoryGenerationMode] = []
        var requests: [StoryGenerationRequest] = []
        var unavailable: String?
        var failure: Error?
        var emptyOnce = false
        var tooLongOnce = false
        var invalidAlways = false
        var pause = false
        private var started = false
        private var waiter: CheckedContinuation<Void, Never>?
        func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String? { unavailable }
        func book(for request: StoryGenerationRequest, mode: StoryGenerationMode) async throws -> GeneratedStoryBook {
            modes.append(mode); requests.append(request); started = true; waiter?.resume(); waiter = nil
            if pause { try await Task.sleep(for: .seconds(30)) }
            if let failure { throw failure }
            var result = Self.validBook
            if tooLongOnce { tooLongOnce = false; result.chapters = result.chapters.map { GeneratedBookChapter(title: $0.title, text: $0.text + " " + $0.text) } }
            if emptyOnce || invalidAlways { emptyOnce = false; result.chapters[0].text = " \n " }
            return result
        }
        func waitForRequest() async {
            if started { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }
}
