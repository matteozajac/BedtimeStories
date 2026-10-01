import Foundation

public struct PlaybackPosition: Codable, Equatable, Sendable {
    public var bookID: UUID
    public var chapterID: UUID?
    public var seconds: Double
    public init(bookID: UUID, chapterID: UUID? = nil, seconds: Double = 0) {
        self.bookID = bookID; self.chapterID = chapterID; self.seconds = seconds
    }
}
