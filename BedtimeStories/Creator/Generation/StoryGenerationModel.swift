import Foundation
import FoundationModels
import Observation

@Observable @MainActor
final class StoryGenerationModel {
    private(set) var working = false
    private(set) var draft: BookDraft?
    private(set) var completedChapterCount = 0
    private(set) var plannedChapterCount = 0
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
        defer { working = false }

        do {
            try request.validate()
            if let reason = generator.unavailabilityReason(for: mode, language: request.language) {
                throw StoryGenerationFailure.unavailable(reason)
            }
            let plan = try await generator.plan(for: request, mode: mode)
            try Task.checkCancellation()
            try plan.validate(chapterCount: request.chapterCount)
            var snapshot = BookDraft()
            snapshot.title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.summary = plan.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.chapters = plan.chapters.map { DraftChapter(title: $0.title) }
            try await save(snapshot)
            draft = snapshot
            var continuity = ""

            for index in plan.chapters.indices {
                try Task.checkCancellation()
                let chapter = try await generator.chapter(for: request, plan: plan, index: index, continuity: continuity, mode: mode)
                try Task.checkCancellation()
                try chapter.validate()
                snapshot.chapters[index].text = chapter.text.trimmingCharacters(in: .whitespacesAndNewlines)
                snapshot.modifiedAt = Date()
                try await save(snapshot)
                draft = snapshot
                completedChapterCount = index + 1
                continuity = chapter.continuity
            }
            try Task.checkCancellation()
            completed = true
        } catch {
            if error is CancellationError || Task.isCancelled {
                message = String(localized: "Creation stopped. Any completed chapters are saved in Your Drafts.")
            } else {
                message = Self.message(for: error)
            }
        }
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
