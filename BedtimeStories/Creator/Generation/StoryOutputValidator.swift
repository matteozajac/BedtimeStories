import Foundation

/// Guided generation guarantees a schema, not nonempty or complete story content.
struct StoryOutputValidator {
    static func validate(_ book: GeneratedStoryBook, request: StoryGenerationRequest) throws -> GeneratedStoryBook {
        let clean = GeneratedStoryBook(title: normalize(book.title), summary: normalize(book.summary), chapters: book.chapters.map {
            GeneratedBookChapter(title: normalize($0.title), text: normalize($0.text))
        }, illustrationGuide: String(normalize(book.illustrationGuide).prefix(500)))
        guard hasLetters(clean.title), clean.title.count <= 160,
              hasLetters(clean.summary), clean.summary.count <= 500,
              (1...request.maximumChapters).contains(clean.chapters.count) else { throw StoryGenerationFailure.invalidResponse }
        var titles = Set<String>()
        var bodies = Set<String>()
        for chapter in clean.chapters {
            let words = StoryReadingLength.wordCount(chapter.text)
            let ending = chapter.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’»)] "))
            guard hasLetters(chapter.title), chapter.title.count <= 120,
                  words >= 60, chapter.text.count <= 100_000,
                  ending.last.map({ ".!?…".contains($0) }) == true,
                  titles.insert(chapter.title.lowercased()).inserted,
                  bodies.insert(chapter.text.lowercased()).inserted else { throw StoryGenerationFailure.invalidResponse }
        }
        let words = clean.chapters.reduce(0) { $0 + StoryReadingLength.wordCount($1.text) }
        guard (request.minimumWords...request.maximumWords).contains(words) else { throw StoryGenerationFailure.durationMismatch }
        return clean
    }

    private static func normalize(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.properties.generalCategory != .format })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}
