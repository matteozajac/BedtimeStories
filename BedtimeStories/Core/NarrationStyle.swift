import Foundation

public enum NarrationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural, gentle, curious, excited, reassuring, whispered

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .natural: String(localized: "Natural")
        case .gentle: String(localized: "Gentle")
        case .curious: String(localized: "Curious")
        case .excited: String(localized: "Excited")
        case .reassuring: String(localized: "Reassuring")
        case .whispered: String(localized: "Whispered")
        }
    }
}
