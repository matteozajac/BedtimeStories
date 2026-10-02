import Foundation
import FoundationModels
import Observation

@Observable @MainActor
final class StoryGenerationModel {
    private(set) var working = false
    private(set) var draft: BookDraft?
    private(set) var completedChapterCount = 0
    private(set) var plannedChapterCount = 0
    private(set) var retrying = false
    private(set) var saving = false
    private(set) var message: String?
    private(set) var completed = false
    private let generator: any StoryGenerating
    let store: BookDraftStore

    init(store: BookDraftStore, generator: any StoryGenerating = FoundationStoryGenerator()) {
        self.store = store
        self.generator = generator
    }

    func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String? {
        generator.unavailabilityReason(for: mode, language: language)
    }

    func generate(_ request: StoryGenerationRequest, mode: StoryGenerationMode) async {
        guard !working else { return }
        working = true
        draft = nil
        completedChapterCount = 0
        plannedChapterCount = request.chapterCount
        message = nil
        completed = false
        retrying = false
        saving = false
        defer { working = false; saving = false }

        do {
            try request.validate()
            if let reason = generator.unavailabilityReason(for: mode, language: request.language) {
                throw StoryGenerationFailure.unavailable(reason)
            }
            var result: GeneratedStoryBook?
            for attempt in 0..<2 {
                try Task.checkCancellation()
                retrying = attempt > 0
                do {
                    let generated = try await generator.book(for: request, mode: mode)
                    try Task.checkCancellation()
                    result = try StoryOutputValidator.validate(generated, chapterCount: request.chapterCount)
                    break
                } catch {
                    guard !Task.isCancelled, attempt == 0, Self.canRetry(error) else { throw error }
                }
            }
            guard let book = result else { throw StoryGenerationFailure.invalidResponse }
            try Task.checkCancellation()
            var snapshot = BookDraft()
            snapshot.title = book.title
            snapshot.summary = book.summary
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
        } catch {
            if error is CancellationError || Task.isCancelled {
                message = String(localized: "Creation stopped. Your previous drafts are safe. Try again when you are ready.")
            } else {
                message = Self.message(for: error)
            }
        }
    }

    private static func canRetry(_ error: Error) -> Bool {
        if case StoryGenerationFailure.invalidResponse = error { return true }
        if error is DecodingError { return true }
        if error is GeneratedContent.ParsingError { return true }
        return false
    }

    private func save(_ snapshot: BookDraft) async throws {
        do { try await store.save(snapshot) }
        catch { throw StoryGenerationFailure.saveFailed }
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
        return failure.errorDescription ?? String(localized: "The story could not be completed. Try again with fewer chapters or a simpler idea.")
    }
}
