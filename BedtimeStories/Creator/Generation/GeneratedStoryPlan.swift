import Foundation
import FoundationModels

@Generable
struct GeneratedStoryPlan: Codable, Sendable {
    @Guide(description: "A short, original book title, at most 100 characters, in the requested language.")
    var title: String
    @Guide(description: "One sentence describing the book, at most 250 characters, in the requested language.")
    var summary: String
    @Guide(description: "Names and consistent traits of the main characters, at most 300 characters.")
    var characters: String
    @Guide(description: "Exactly the requested number of chapters, forming one complete story with a peaceful ending.", .count(1...4))
    var chapters: [GeneratedChapterPlan]

    func validate(chapterCount: Int) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 160, summary.count <= 400, characters.count <= 400,
              chapters.count == chapterCount,
              chapters.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 120 && !$0.plot.isEmpty && $0.plot.count <= 400 }) else {
            throw StoryGenerationFailure.invalidResponse
        }
    }
}
