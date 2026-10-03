import Foundation

@MainActor
protocol CloudStoryGenerating {
    var storyUnavailabilityReason: String? { get }
    func generateStory(_ request: StoryGenerationRequest) async throws -> GeneratedStoryBook
}

@MainActor
final class StoryGenerator: StoryGenerating {
    private let apple: any StoryGenerating
    private let cloud: any CloudStoryGenerating

    init(cloud: any CloudStoryGenerating, apple: any StoryGenerating = FoundationStoryGenerator()) {
        self.cloud = cloud
        self.apple = apple
    }

    func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String? {
        mode == .gemini ? cloud.storyUnavailabilityReason : apple.unavailabilityReason(for: mode, language: language)
    }

    func book(for request: StoryGenerationRequest, mode: StoryGenerationMode) async throws -> GeneratedStoryBook {
        try request.validate(mode: mode)
        try Task.checkCancellation()
        if mode == .gemini { return try await cloud.generateStory(request) }
        return try await apple.book(for: request, mode: mode)
    }
}

extension CloudNarrationModel: CloudStoryGenerating {
    var storyUnavailabilityReason: String? {
        guard isConfigured, isEnabled else { return StoryGenerationFailure.geminiUnavailable.errorDescription }
        return userID == nil ? StoryGenerationFailure.geminiSignInRequired.errorDescription : nil
    }
}
