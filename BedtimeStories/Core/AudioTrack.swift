import Foundation

public struct AudioTrack: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var chapterID: UUID?
    public var title: String
    public init(path: String, chapterID: UUID?, title: String) {
        self.path = path; self.chapterID = chapterID; self.title = title
    }
    public static func tracks(for book: BookManifest) -> [AudioTrack] {
        if let path = book.audio { return [AudioTrack(path: path, chapterID: nil, title: book.title)] }
        return book.orderedChapters.enumerated().compactMap { index, chapter in
            guard let audio = chapter.audio else { return nil }
            return AudioTrack(path: audio, chapterID: chapter.id, title: chapter.title ?? "\(index + 1)")
        }
    }
    public static func chapter(at seconds: Double, in book: BookManifest) -> BookChapter? {
        guard book.audio != nil else { return nil }
        return book.orderedChapters.last { ($0.startTime ?? .infinity) <= seconds }
    }
    public static func nextBoundary(after seconds: Double, in book: BookManifest, duration: Double) -> Double? {
        if let next = book.orderedChapters.compactMap(\.startTime).first(where: { $0 > seconds + 0.1 }) { return next }
        return book.orderedChapters.contains(where: { $0.startTime != nil }) && duration > 0 ? duration : nil
    }
}
