import Foundation

enum ReadingDuration: Int, CaseIterable, Codable {
    case five = 5
    case ten = 10
    case fifteen = 15
    
    var displayText: String {
        switch self {
        case .five:
            return "5 minutes"
        case .ten:
            return "10 minutes"
        case .fifteen:
            return "15 minutes"
        }
    }
}

struct Story: Identifiable, Codable {
    let id = UUID()
    let title: String
    let content: String?
    let duration: ReadingDuration
    let description: String?
    let favoriteCharacters: String?
    let createdAt: Date
    
    init(title: String, content: String? = nil, duration: ReadingDuration = .ten, description: String? = nil, favoriteCharacters: String? = nil) {
        self.title = title
        self.content = content
        self.duration = duration
        self.description = description
        self.favoriteCharacters = favoriteCharacters
        self.createdAt = Date()
    }
}
