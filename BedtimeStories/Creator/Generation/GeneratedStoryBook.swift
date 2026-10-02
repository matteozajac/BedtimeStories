import FoundationModels

@Generable
struct GeneratedStoryBook: Codable, Sendable {
    @Guide(description: "A short original book title in the requested language.")
    var title: String
    @Guide(description: "One sentence describing this story in the requested language.")
    var summary: String
    @Guide(description: "Exactly the requested number of fully written chapters, in order. One connected story with consistent characters, a beginning, events, and a peaceful resolution in the last chapter.", .count(1...4))
    var chapters: [GeneratedBookChapter]
}
