import Foundation

enum StoryLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english, polish

    var id: Self { self }
    var locale: Locale { Locale(identifier: self == .polish ? "pl_PL" : "en_US") }
    var title: String { self == .polish ? "Polski" : "English" }
    var promptName: String { self == .polish ? "Polish" : "English" }
    static var preferred: Self { Locale.current.language.languageCode?.identifier == "pl" ? .polish : .english }
}
