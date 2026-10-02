import Foundation

struct NarrationOutput: Codable, Equatable, Sendable {
    let chapterId: String
    let path: String
    let sha256: String
    let bytes: Int
    let duration: Double
}
