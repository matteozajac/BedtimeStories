import Foundation

@MainActor
protocol StoryGenerating {
    func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String?
    func book(for request: StoryGenerationRequest, mode: StoryGenerationMode) async throws -> GeneratedStoryBook
}
