import Foundation

/// Guided generation guarantees a schema, not nonempty or complete story content.
struct StoryOutputValidator {
    static func validate(_ book: GeneratedStoryBook, chapterCount: Int) throws -> GeneratedStoryBook {
        let clean = GeneratedStoryBook(title: normalize(book.title), summary: normalize(book.summary), chapters: book.chapters.map {
            GeneratedBookChapter(title: normalize($0.title), text: normalize($0.text))
        })
        guard hasLetters(clean.title), clean.title.count <= 160,
              hasLetters(clean.summary), clean.summary.count <= 500,
              clean.chapters.count == chapterCount else { throw StoryGenerationFailure.invalidResponse }
        var titles = Set<String>()
        var bodies = Set<String>()
        for chapter in clean.chapters {
            let words = chapter.text.split(whereSeparator: \.isWhitespace).filter { hasLetters(String($0)) }.count
            let ending = chapter.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’»)] "))
            guard hasLetters(chapter.title), chapter.title.count <= 120,
                  words >= 60, chapter.text.count <= 3_500,
                  ending.last.map({ ".!?…".contains($0) }) == true,
                  titles.insert(chapter.title.lowercased()).inserted,
                  bodies.insert(chapter.text.lowercased()).inserted else { throw StoryGenerationFailure.invalidResponse }
        }
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
