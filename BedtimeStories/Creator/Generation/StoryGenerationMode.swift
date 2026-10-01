import Foundation

enum StoryGenerationMode: String, CaseIterable, Identifiable, Sendable {
    case onDevice, privateCloud

    var id: Self { self }

    var title: String {
        switch self {
        case .onDevice: String(localized: "On This Device")
        case .privateCloud: String(localized: "Private Cloud Compute")
        }
    }
}
