import Foundation

struct LibraryScan: Sendable {
    var books: [LibraryBook]
    var warnings: [String]
    var isOffline: Bool
}
