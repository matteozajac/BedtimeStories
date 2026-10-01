import Foundation

public enum BookError: Error, LocalizedError, Sendable {
    case invalid(String)
    case unavailable(String)
    case duplicate

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason), .unavailable(let reason): reason
        case .duplicate: "A book with this identity already exists."
        }
    }
}
