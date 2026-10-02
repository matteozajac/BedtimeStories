import Foundation

struct VoiceProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let language: String
    let status: String
    var createdAt: Double = 0
    var errorCode: String? = nil
}
