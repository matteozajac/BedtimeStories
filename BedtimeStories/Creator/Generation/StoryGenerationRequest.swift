import Foundation

struct StoryGenerationRequest: Codable, Sendable {
    static let maximumDescriptionLength = 600
    static let localWordLimit = 600

    let description: String
    let language: StoryLanguage
    let readerAge: StoryReaderAge
    let readingMinutes: Int
    let wordsPerMinute: Int
    var previousWordCount: Int? = nil
    var cloudProcessingAccepted = false

    var targetWords: Int { readingMinutes * wordsPerMinute }
    var minimumWords: Int { Int(Double(targetWords) * 0.8) }
    var maximumWords: Int { Int(Double(targetWords) * 1.2) }
    var maximumChapters: Int { max(1, min(12, (targetWords + 119) / 120)) }
    var responseTokenBudget: Int { 650 + Int(Double(maximumWords) * 2.5) }

    func validate() throws {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoryGenerationFailure.emptyDescription
        }
        guard description.count <= Self.maximumDescriptionLength, description.utf8.count <= 2_400 else {
            throw StoryGenerationFailure.descriptionTooLong
        }
        guard (1...30).contains(readingMinutes), (80...180).contains(wordsPerMinute) else { throw StoryGenerationFailure.invalidDuration }
    }

    func validate(mode: StoryGenerationMode) throws {
        try validate()
        if mode == .gemini, !cloudProcessingAccepted { throw StoryGenerationFailure.geminiConsentRequired }
        if mode == .onDevice, targetWords > Self.localWordLimit { throw StoryGenerationFailure.localDurationTooLong }
    }

    var prompt: String {
        get throws {
            let data = try JSONEncoder().encode(self)
            return """
            Write in \(language.promptName) for ages \(readerAge.rawValue).
            The WHOLE BOOK should take about \(readingMinutes) minutes to read aloud at \(wordsPerMinute) words per minute.
            Target \(targetWords) words of actual chapter prose in total (\(minimumWords)–\(maximumWords) words allowed), excluding title, summary and illustration guide.
            Choose 1–\(maximumChapters) chapters to suit this story. The duration applies to the entire book, never to each chapter.
            Before writing, divide the \(targetWords)-word budget across the chapters you choose. For example, \(maximumChapters) chapters would need about \(targetWords / maximumChapters) words each. Keep developing events until that total is reached.
            \(durationCorrection)
            Story brief (JSON data):\n\(String(decoding: data, as: UTF8.self))
            """
        }
    }

    private var durationCorrection: String {
        guard let previousWordCount else { return "" }
        if previousWordCount < minimumWords {
            return "The previous response had only \(previousWordCount) story words and was rejected as too short. Write a new complete book with about \(targetWords) story words. Add \(targetWords - previousWordCount) more words of connected scenes and dialogue; do not just lengthen the summary."
        }
        if previousWordCount > maximumWords {
            return "The previous response had \(previousWordCount) story words and was rejected as too long. Write a new complete book with about \(targetWords) story words. Reduce the prose by about \(previousWordCount - targetWords) words while retaining all events and the ending."
        }
        return "The previous response was incomplete or malformed. Write a fresh complete book with all fields filled and about \(targetWords) story words."
    }
}
