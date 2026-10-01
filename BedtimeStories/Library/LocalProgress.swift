import Foundation

@MainActor
final class LocalProgress {
    private let defaults: UserDefaults
    private let namespace: String
    init(namespace: String, defaults: UserDefaults = .standard) { self.namespace = namespace; self.defaults = defaults }
    func playback(_ id: UUID) -> PlaybackPosition? {
        defaults.data(forKey: namespace + ".audio." + id.uuidString).flatMap { try? JSONDecoder().decode(PlaybackPosition.self, from: $0) }
    }
    func save(_ position: PlaybackPosition) {
        if let data = try? JSONEncoder().encode(position) { defaults.set(data, forKey: namespace + ".audio." + position.bookID.uuidString) }
        defaults.set(position.bookID.uuidString, forKey: namespace + ".lastBook")
    }
    var lastBookID: UUID? { defaults.string(forKey: namespace + ".lastBook").flatMap(UUID.init(uuidString:)) }
    func readingChapter(_ id: UUID) -> UUID? { defaults.string(forKey: namespace + ".reading." + id.uuidString).flatMap(UUID.init(uuidString:)) }
    func saveReading(_ chapterID: UUID, bookID: UUID) { defaults.set(chapterID.uuidString, forKey: namespace + ".reading." + bookID.uuidString) }
}
