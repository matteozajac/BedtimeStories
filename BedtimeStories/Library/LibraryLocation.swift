import Foundation

struct LibraryLocation: Equatable, Sendable {
    let root: URL
    let isCloud: Bool
    let account: String
}
