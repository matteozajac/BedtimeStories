import CryptoKit
import Foundation

/// An immutable narration request. This is private processing data, never a book asset.
public struct NarrationSnapshot: Codable, Equatable, Sendable {
    public struct Paragraph: Codable, Equatable, Sendable {
        public let text: String
        public let style: NarrationStyle
    }
    public struct Chapter: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let sourceText: String
        public let paragraphs: [Paragraph]
    }

    public let draftId: String
    public let chapters: [Chapter]

    public init(draft: BookDraft, styles: [UUID: [NarrationStyle]], defaultStyle: NarrationStyle) {
        draftId = draft.id.uuidString
        chapters = draft.chapters.map { chapter in
            let blocks = Self.paragraphs(in: chapter)
            let selected = styles[chapter.id] ?? []
            return Chapter(id: chapter.id.uuidString, title: chapter.title, sourceText: chapter.text,
                           paragraphs: blocks.enumerated().map { index, text in
                Paragraph(text: text, style: index < selected.count ? selected[index] : defaultStyle)
            })
        }
    }

    public static func paragraphs(in chapter: DraftChapter) -> [String] {
        StoryTextBlock.parse(chapter.text, markdown: true, omittingTitle: chapter.title)
            .map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var hash: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return SHA256.hash(data: try encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
        }
    }
}
