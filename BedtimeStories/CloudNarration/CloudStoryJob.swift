import Foundation

struct CloudStoryJob: Decodable, Sendable, Identifiable {
    let id: String
    let state: String
    var progress: Double = 0
    var result: GeneratedStoryBook?
    var createdAt: Double = 0
    var expiresAt: Double = 0
    var errorCode: String?
    var wordsPerMinute: Int?
}
