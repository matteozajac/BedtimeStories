import FoundationModels

@Generable
struct GeneratedBookChapter: Codable, Sendable {
    @Guide(description: "A short, distinct chapter title in the requested language.")
    var title: String
    @Guide(description: "Complete story prose in short paragraphs. Use enough words so all chapters together meet the entire book's requested reading duration. At least 60 words. Never empty. No heading, outline, instructions, or commentary. Finish every sentence.")
    var text: String
}
