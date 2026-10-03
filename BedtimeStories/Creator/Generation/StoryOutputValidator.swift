import Foundation
import MZAppFoundation

/// Guided generation guarantees a schema, not nonempty or complete story content.
struct StoryOutputValidator {
    @MainActor static func validate(_ book: GeneratedStoryBook, request: StoryGenerationRequest,
                         logger: any AppLogging = AppLog.logger,
                         metadata: [String: TelemetryValue] = [:]) throws -> GeneratedStoryBook {
        let clean = GeneratedStoryBook(title: normalize(book.title), summary: normalize(book.summary), chapters: book.chapters.map {
            GeneratedBookChapter(title: normalize($0.title), text: normalize($0.text))
        }, illustrationGuide: String(normalize(book.illustrationGuide).prefix(500)))
        @MainActor func reject(_ reason: String, chapterIndex: Int? = nil, wordCount: Int? = nil,
                    failure: StoryGenerationFailure = .invalidResponse,
                    file: String = #fileID, function: String = #function, line: UInt = #line) throws -> Never {
            var fields = metadata
            fields["validation_reason"] = .string(reason)
            if let chapterIndex { fields["chapter_index"] = .integer(chapterIndex) }
            if let wordCount { fields["actual_words"] = .integer(wordCount) }
            // The generation boundary owns the Error report. This trace explains
            // the precise validation checkpoint without copying generated prose.
            logger.trace("Generated story validation rejected its response", category: "creator", metadata: fields,
                         file: file, function: function, line: line)
            throw failure
        }
        guard hasLetters(clean.title), clean.title.count <= 160 else { try reject("invalid_book_title") }
        guard hasLetters(clean.summary), clean.summary.count <= 500 else { try reject("invalid_book_summary") }
        guard (1...request.maximumChapters).contains(clean.chapters.count) else { try reject("invalid_chapter_count") }
        var titles = Set<String>()
        var bodies = Set<String>()
        for (index, chapter) in clean.chapters.enumerated() {
            let words = StoryReadingLength.wordCount(chapter.text)
            let ending = chapter.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’»)] "))
            guard hasLetters(chapter.title), chapter.title.count <= 120 else { try reject("invalid_chapter_title", chapterIndex: index) }
            guard words >= 60 else { try reject("chapter_prose_too_short", chapterIndex: index, wordCount: words) }
            guard chapter.text.count <= 100_000 else { try reject("chapter_prose_too_large", chapterIndex: index, wordCount: words) }
            guard ending.last.map({ ".!?…".contains($0) }) == true else { try reject("incomplete_final_sentence", chapterIndex: index) }
            guard titles.insert(chapter.title.lowercased()).inserted else { try reject("duplicate_chapter_title", chapterIndex: index) }
            guard bodies.insert(chapter.text.lowercased()).inserted else { try reject("duplicate_chapter_prose", chapterIndex: index) }
        }
        let words = clean.chapters.reduce(0) { $0 + StoryReadingLength.wordCount($1.text) }
        guard (request.minimumWords...request.maximumWords).contains(words) else { try reject("book_reading_length_mismatch", wordCount: words, failure: .durationMismatch) }
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
