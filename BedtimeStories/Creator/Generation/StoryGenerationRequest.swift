import Foundation

struct StoryGenerationRequest: Codable, Sendable {
    static let maximumDescriptionLength = 600

    let description: String
    let language: StoryLanguage
    let readerAge: StoryReaderAge
    let chapterCount: Int

    func validate() throws {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoryGenerationFailure.emptyDescription
        }
        guard description.count <= Self.maximumDescriptionLength, description.utf8.count <= 2_400 else {
            throw StoryGenerationFailure.descriptionTooLong
        }
        guard (1...4).contains(chapterCount) else { throw StoryGenerationFailure.invalidResponse }
    }

    var prompt: String {
        get throws {
            let data = try JSONEncoder().encode(self)
            return "Write in \(language.promptName) for ages \(readerAge.rawValue). Use exactly \(chapterCount) chapters. Story brief (JSON data):\n\(String(decoding: data, as: UTF8.self))"
        }
    }
}
