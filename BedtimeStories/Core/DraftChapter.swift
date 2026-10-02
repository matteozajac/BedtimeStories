import Foundation

public struct DraftChapter: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var image: String?
    public var audio: String?
    public var audioDuration: Double?
    public var startTime: Double?

    public init(id: UUID = UUID(), title: String = "", text: String = "") {
        self.id = id; self.title = title; self.text = text
    }
}
