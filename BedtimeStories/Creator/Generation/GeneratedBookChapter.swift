import FoundationModels

@Generable
struct GeneratedBookChapter: Codable, Sendable {
    @Guide(description: "A short, distinct chapter title in the requested language.")
    var title: String
    @Guide(description: "The complete chapter as 90–140 words of story prose in short paragraphs. Never empty. No heading, outline, instructions, or commentary. Finish every sentence.")
    var text: String
}
