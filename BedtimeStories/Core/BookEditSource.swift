import Foundation

/// A local checkout token, never included in a published book.
public struct BookEditSource: Codable, Hashable, Sendable {
    public let bookID: UUID
    public let libraryRoot: URL
    public let fingerprint: String
    public let libraryAccount: String?

    public init(bookID: UUID, libraryRoot: URL, fingerprint: String, libraryAccount: String? = nil) {
        self.bookID = bookID; self.libraryRoot = libraryRoot; self.fingerprint = fingerprint; self.libraryAccount = libraryAccount
    }
}
