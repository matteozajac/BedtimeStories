import Foundation

public struct BookChapter: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String?
    public var text: String?
    public var image: String?
    public var audio: String?
    public var startTime: Double?

    public init(id: UUID = UUID(), title: String? = nil, text: String? = nil, image: String? = nil, audio: String? = nil, startTime: Double? = nil) {
        self.id = id; self.title = title; self.text = text; self.image = image; self.audio = audio; self.startTime = startTime
    }
}
