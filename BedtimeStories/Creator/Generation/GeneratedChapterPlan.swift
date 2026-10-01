import FoundationModels

@Generable
struct GeneratedChapterPlan: Codable, Sendable {
    @Guide(description: "A short chapter title in the requested language, at most 80 characters.")
    var title: String
    @Guide(description: "What happens in this chapter, at most 250 characters. Resolve the story in the final chapter.")
    var plot: String
}
