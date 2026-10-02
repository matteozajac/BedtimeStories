import Foundation

struct VoiceEnrollment: Codable, Sendable {
    let enrollmentId: String
    let expiresAt: Double
    let consentStatement: String
}
