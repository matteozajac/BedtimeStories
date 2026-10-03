import Foundation
import MZAppFoundation

@MainActor
final class LocalProgress {
    private let defaults: UserDefaults
    private let namespace: String
    private let logger: any AppLogging
    private var failedReadData: [UUID: Data] = [:]
    private var invalidIdentityKeys = Set<String>()

    init(namespace: String, defaults: UserDefaults = .standard, logger: any AppLogging = AppLog.logger) {
        self.namespace = namespace; self.defaults = defaults; self.logger = logger
    }

    func playback(_ id: UUID) -> PlaybackPosition? {
        guard let data = defaults.data(forKey: namespace + ".audio." + id.uuidString) else { return nil }
        do {
            let position = try JSONDecoder().decode(PlaybackPosition.self, from: data)
            failedReadData[id] = nil
            return position
        } catch {
            // This lookup is also used by view rendering. Report a corrupt value
            // once until its contents change, rather than once per rendered row.
            if failedReadData[id] != data {
                failedReadData[id] = data
                logger.warning("Saved playback position could not be restored", error: error, category: "library", metadata: [
                    "book_id": .string(id.uuidString), "data_bytes": .integer(data.count), "recovery": .string("start_from_beginning")
                ])
            }
            return nil
        }
    }
    func save(_ position: PlaybackPosition) {
        do {
            let data = try JSONEncoder().encode(position)
            defaults.set(data, forKey: namespace + ".audio." + position.bookID.uuidString)
            failedReadData[position.bookID] = nil
        } catch {
            logger.warning("Playback position could not be saved", error: error, category: "library", metadata: [
                "book_id": .string(position.bookID.uuidString), "has_chapter": .bool(position.chapterID != nil)
            ])
        }
        defaults.set(position.bookID.uuidString, forKey: namespace + ".lastBook")
    }
    var lastBookID: UUID? { storedIdentity(key: namespace + ".lastBook", kind: "last_book") }
    func readingChapter(_ id: UUID) -> UUID? { storedIdentity(key: namespace + ".reading." + id.uuidString, kind: "reading_chapter", bookID: id) }
    func saveReading(_ chapterID: UUID, bookID: UUID) { defaults.set(chapterID.uuidString, forKey: namespace + ".reading." + bookID.uuidString) }

    private func storedIdentity(key: String, kind: String, bookID: UUID? = nil) -> UUID? {
        guard let stored = defaults.string(forKey: key) else { return nil }
        guard let identity = UUID(uuidString: stored) else {
            if invalidIdentityKeys.insert(key).inserted {
                var fields: [String: TelemetryValue] = ["progress_kind": .string(kind), "recovery": .string("ignore_saved_position")]
                if let bookID { fields["book_id"] = .string(bookID.uuidString) }
                logger.warning("Saved library progress has an invalid identity", category: "library", metadata: fields)
            }
            return nil
        }
        invalidIdentityKeys.remove(key)
        return identity
    }
}
