import Foundation

@MainActor
protocol StoryGenerating {
    func unavailabilityReason(for mode: StoryGenerationMode, language: StoryLanguage) -> String?
    func plan(for request: StoryGenerationRequest, mode: StoryGenerationMode) async throws -> GeneratedStoryPlan
    func chapter(for request: StoryGenerationRequest, plan: GeneratedStoryPlan, index: Int, continuity: String, mode: StoryGenerationMode) async throws -> GeneratedStoryChapter
}
