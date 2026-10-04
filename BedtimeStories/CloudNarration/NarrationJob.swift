import Foundation

struct NarrationJob: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let state: String
    let progress: Double
    let draftId: String
    let snapshotHash: String
    var voiceProfileId: String?
    var preview: Bool = false
    var outputs: [NarrationOutput] = []
    var createdAt: Double = 0
    var expiresAt: Double = 0
    var errorCode: String? = nil
}
