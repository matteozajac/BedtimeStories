import Foundation
import FoundationModels

@Generable
struct GeneratedStoryChapter: Sendable {
    @Guide(description: "The finished chapter in the requested language: 120–180 words in short paragraphs. Plain story text without a heading or commentary. Finish every sentence.")
    var text: String
    @Guide(description: "Continuity notes for the next chapter: key events and where the characters are now, at most 250 characters.")
    var continuity: String

    func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 3_500, continuity.count <= 400 else {
            throw StoryGenerationFailure.invalidResponse
        }
    }
}
