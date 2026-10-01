import Foundation

enum StoryReaderAge: String, CaseIterable, Identifiable, Codable, Sendable {
    case preschool = "3–5", earlySchool = "6–8", olderChildren = "9–12"

    var id: Self { self }
}
