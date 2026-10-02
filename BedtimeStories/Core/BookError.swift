import Foundation

public enum BookError: Error, LocalizedError, Sendable {
    case invalid(String)
    case unavailable(String)
    case duplicate
    case editConflict

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason), .unavailable(let reason): reason
        case .duplicate: "A book with this identity already exists."
        case .editConflict: String(localized: "This book changed after you opened it. Your edits are safe on this device. Save them as a new book, or close and reopen the latest library version.")
        }
    }
}
