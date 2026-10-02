import Foundation
import FoundationModels
import MZAppFoundation
import Observation

@Observable @MainActor
final class StoryGenerationModel {
    private(set) var working = false
    private(set) var draft: BookDraft?
    private(set) var completedChapterCount = 0
    private(set) var retrying = false
    private(set) var saving = false
    private(set) var message: String?
    private(set) var completed = false
    private let generator: any StoryGenerating
    let store: BookDraftStore
    @ObservationIgnored private let logger: any AppLogging

    init(store: BookDraftStore, generator: any StoryGenerating = FoundationStoryGenerator(),
         logger: any AppLogging = AppLog.logger) {
        self.store = store
        self.generator = generator
        self.logger = logger
    }

    func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String? {
        generator.unavailabilityReason(for: mode, language: language)
    }

    func generate(_ request: StoryGenerationRequest, mode: StoryGenerationMode) async {
        guard !working else { return }
        working = true
        draft = nil
        completedChapterCount = 0
        message = nil
        completed = false
        retrying = false
        saving = false
        logger.log(LogEntry("Story creation started", category: "creator", metadata: ["mode": .string(mode.rawValue)]))
        defer { working = false; saving = false }

        do {
            try request.validate(mode: mode)
            if let reason = generator.unavailabilityReason(for: mode, language: request.language) {
                throw StoryGenerationFailure.unavailable(reason)
            }
            var result: GeneratedStoryBook?
            var attemptRequest = request
            for attempt in 0..<2 {
                try Task.checkCancellation()
                retrying = attempt > 0
                do {
                    let generated = try await generator.book(for: attemptRequest, mode: mode)
                    try Task.checkCancellation()
                    attemptRequest.previousWordCount = generated.chapters.reduce(0) { $0 + StoryReadingLength.wordCount($1.text) }
                    result = try StoryOutputValidator.validate(generated, request: request)
                    break
                } catch {
                    guard !Task.isCancelled, attempt == 0, Self.canRetry(error) else { throw error }
                    logger.log(LogEntry("Story creation retry", level: .warning, category: "creator", error: ErrorSnapshot(error)))
                }
            }
            guard let book = result else { throw StoryGenerationFailure.invalidResponse }
            try Task.checkCancellation()
            var snapshot = BookDraft()
            snapshot.title = book.title
            snapshot.summary = book.summary
            snapshot.readingWordsPerMinute = request.wordsPerMinute
            snapshot.illustrationGuide = book.illustrationGuide.isEmpty ? nil : book.illustrationGuide
            snapshot.chapters = book.chapters.map {
                var chapter = DraftChapter(title: $0.title)
                chapter.text = $0.text
                return chapter
            }
            saving = true
            try await save(snapshot)
            draft = snapshot
            completedChapterCount = snapshot.chapters.count
            try Task.checkCancellation()
            completed = true
            logger.log(LogEntry("Story draft created", category: "creator", metadata: ["chapter_count": .integer(snapshot.chapters.count)]))
        } catch {
            if error is CancellationError || Task.isCancelled {
                message = String(localized: "Creation stopped. Your previous drafts are safe. Try again when you are ready.")
            } else {
                if case StoryGenerationFailure.saveFailed = error { /* Already recorded with its underlying error. */ }
                else { logger.error("Story creation failed", error: error, category: "creator") }
                message = Self.message(for: error)
            }
        }
    }

    private static func canRetry(_ error: Error) -> Bool {
        if case StoryGenerationFailure.invalidResponse = error { return true }
        if case StoryGenerationFailure.durationMismatch = error { return true }
        if error is DecodingError { return true }
        if error is GeneratedContent.ParsingError { return true }
        return false
    }

    private func save(_ snapshot: BookDraft) async throws {
        do { try await store.save(snapshot) }
        catch {
            logger.error("Generated draft save failed", error: error, category: "creator")
            throw StoryGenerationFailure.saveFailed
        }
    }

    static func message(for error: Error) -> String {
        let failure: StoryGenerationFailure
        switch error {
        case let error as StoryGenerationFailure: failure = error
        case let error as LanguageModelError:
            switch error {
            case .guardrailViolation, .refusal: failure = .refused
            case .contextSizeExceeded: failure = .contextTooLong
            case .unsupportedLanguageOrLocale: failure = .unsupportedLanguage
            case .rateLimited: failure = .busy
            default: failure = .generationFailed
            }
        case let error as PrivateCloudComputeLanguageModel.Error:
            switch error {
            case .networkFailure: failure = .cloudNetwork
            case .quotaLimitReached: failure = .cloudQuota
            case .serviceUnavailable: failure = .cloudUnavailable
            @unknown default: failure = .cloudUnavailable
            }
        case is SystemLanguageModel.Error: failure = .generationFailed
        default: failure = .generationFailed
        }
        return failure.errorDescription ?? String(localized: "The story could not be completed. Try again with a shorter reading time or a simpler idea.")
    }
}
