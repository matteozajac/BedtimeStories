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
        guard !working else {
            logger.warning("Story creation ignored because another generation is running", category: "creator", metadata: ["mode": .string(mode.rawValue)])
            return
        }
        working = true
        draft = nil
        completedChapterCount = 0
        message = nil
        completed = false
        retrying = false
        saving = false
        let operationID = UUID().uuidString
        var fields: [String: TelemetryValue] = ["diagnostic_operation_id": .string(operationID), "mode": .string(mode.rawValue),
            "language": .string(request.language.rawValue), "reading_minutes": .integer(request.readingMinutes),
            "words_per_minute": .integer(request.wordsPerMinute)]
        logger.log(LogEntry("Story creation started", category: "creator", metadata: fields))
        let started = ContinuousClock.now
        var phase = "validation"
        defer { working = false; saving = false }

        do {
            try request.validate(mode: mode)
            fields["minimum_words"] = .integer(request.minimumWords)
            fields["maximum_words"] = .integer(request.maximumWords)
            let availabilityCode = (generator as? FoundationStoryGenerator)?.availabilityCode(for: mode, language: request.language)
            logger.debug("Story creation model availability checked", category: "creator", metadata: fields.merging(["availability": .string(availabilityCode ?? "custom_generator")]) { _, new in new })
            if let reason = generator.unavailabilityReason(for: mode, language: request.language) {
                throw StoryGenerationFailure.unavailable(reason)
            }
            var result: GeneratedStoryBook?
            var attemptRequest = request
            for attempt in 0..<2 {
                try Task.checkCancellation()
                retrying = attempt > 0
                phase = "generation"
                logger.trace("Story generation request started", category: "creator", metadata: fields.merging(["attempt": .integer(attempt + 1)]) { _, new in new })
                do {
                    let generated = try await generator.book(for: attemptRequest, mode: mode)
                    logger.trace("Story generation response received", category: "creator", metadata: fields.merging(["attempt": .integer(attempt + 1), "chapter_count": .integer(generated.chapters.count)]) { _, new in new })
                    try Task.checkCancellation()
                    attemptRequest.previousWordCount = generated.chapters.reduce(0) { $0 + StoryReadingLength.wordCount($1.text) }
                    phase = "response_validation"
                    logger.trace("Generated story completeness validation started", category: "creator", metadata: fields.merging([
                        "attempt": .integer(attempt + 1), "actual_words": .integer(attemptRequest.previousWordCount ?? 0),
                        "chapter_count": .integer(generated.chapters.count)
                    ]) { _, new in new })
                    result = try StoryOutputValidator.validate(generated, request: request, logger: logger, metadata: fields.merging(["attempt": .integer(attempt + 1)]) { _, new in new })
                    logger.debug("Generated story completeness validation completed", category: "creator", metadata: fields.merging(["attempt": .integer(attempt + 1)]) { _, new in new })
                    break
                } catch {
                    guard !Task.isCancelled, mode != .gemini, attempt == 0, Self.canRetry(error) else { throw error }
                    logger.warning("Story creation retry", error: error, category: "creator", metadata: fields.merging(["phase": .string(phase), "attempt": .integer(attempt + 1), "actual_words": .integer(attemptRequest.previousWordCount ?? 0), "failure_reason": .string(Self.technicalFailureMessage(for: error))]) { _, new in new })
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
            phase = "draft_save"
            logger.trace("Generated story draft save started", category: "creator", metadata: fields.merging(["chapter_count": .integer(snapshot.chapters.count)]) { _, new in new })
            try await save(snapshot, metadata: fields)
            draft = snapshot
            completedChapterCount = snapshot.chapters.count
            try Task.checkCancellation()
            completed = true
            logger.log(LogEntry("Story draft created", category: "creator", metadata: fields.merging(["chapter_count": .integer(snapshot.chapters.count), "elapsed_ms": .integer(Self.elapsedMilliseconds(since: started))]) { _, new in new }))
        } catch {
            if ErrorSnapshot.isCancellation(error) || Task.isCancelled {
                logger.trace("Story creation cancelled", category: "creator", metadata: fields.merging(["phase": .string(phase), "elapsed_ms": .integer(Self.elapsedMilliseconds(since: started))]) { _, new in new })
                message = String(localized: "Creation stopped. Your previous drafts are safe. Try again when you are ready.")
            } else {
                if case StoryGenerationFailure.saveFailed = error { /* Already recorded with its underlying error. */ }
                else { logger.error("Story creation failed", error: error, category: "creator", metadata: fields.merging(["phase": .string(phase), "elapsed_ms": .integer(Self.elapsedMilliseconds(since: started)), "failure_reason": .string(Self.technicalFailureMessage(for: error))]) { _, new in new }) }
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

    private func save(_ snapshot: BookDraft, metadata: [String: TelemetryValue]) async throws {
        do { try await store.save(snapshot) }
        catch is CancellationError { throw CancellationError() }
        catch {
            logger.error("Generated draft save failed", error: error, category: "creator", metadata: metadata)
            throw StoryGenerationFailure.saveFailed
        }
    }

    private static func elapsedMilliseconds(since started: ContinuousClock.Instant) -> Int {
        let elapsed = started.duration(to: .now).components
        return Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
    }

    static func technicalFailureMessage(for error: Error) -> String { classifiedFailure(for: error).logMessage }

    static func message(for error: Error) -> String {
        classifiedFailure(for: error).errorDescription ?? String(localized: "The story could not be completed. Try again with a shorter reading time or a simpler idea.")
    }

    private static func classifiedFailure(for error: Error) -> StoryGenerationFailure {
        let failure: StoryGenerationFailure
        switch error {
        case let context as CloudNarrationFailureContext: return classifiedFailure(for: context.presentation)
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
        return failure
    }
}
