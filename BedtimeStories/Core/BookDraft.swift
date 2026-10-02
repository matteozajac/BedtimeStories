import Foundation

public struct BookDraft: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title = ""
    public var author = ""
    public var summary = ""
    public var cover: String?
    public var audio: String?
    public var audioDuration: Double?
    public var source: BookEditSource?
    public var readingWordsPerMinute: Int?
    public var illustrationGuide: String?
    public var chapters: [DraftChapter]
    public var modifiedAt: Date

    public init(id: UUID = UUID()) {
        self.id = id; chapters = [DraftChapter()]; modifiedAt = Date()
    }

    public var manifest: BookManifest {
        var result = BookManifest(id: source?.bookID ?? id, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: Self.optional(author), description: Self.optional(summary), cover: cover,
            audio: audio,
            chapters: chapters.map { chapter in
                BookChapter(id: chapter.id, title: Self.optional(chapter.title),
                    text: Self.optional(chapter.text) == nil ? nil : "text/\(chapter.id.uuidString).md",
                    image: chapter.image, audio: chapter.audio, startTime: chapter.startTime)
            })
        result.readingWordsPerMinute = readingWordsPerMinute
        result.illustrationGuide = illustrationGuide
        return result
    }

    public var mediaPaths: [String] { ([cover, audio] + chapters.flatMap { [$0.image, $0.audio] }).compactMap { $0 } }
    public var wordCount: Int { chapters.reduce(0) { $0 + StoryReadingLength.wordCount($1.text) } }

    public func hasSameContent(as other: BookDraft) -> Bool {
        var a = self; var b = other
        a.modifiedAt = .distantPast; b.modifiedAt = .distantPast
        return a == b
    }

    public var isEmpty: Bool {
        title.isEmpty && author.isEmpty && summary.isEmpty && mediaPaths.isEmpty && chapters.allSatisfy { $0.title.isEmpty && $0.text.isEmpty }
    }

    public func validateDraft() throws {
        guard chapters.count <= 9_999, Set(chapters.map(\.id)).count == chapters.count else {
            throw BookError.invalid("Chapter identities must be unique.")
        }
        for path in mediaPaths { try SafeBookPath.validate(path) }
        guard chapters.allSatisfy({ $0.text.utf8.count <= 5_000_000 }) else {
            throw BookError.invalid("Chapter text is too large to display.")
        }
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
