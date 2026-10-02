import CryptoKit
import Foundation

/// Cloud-only preferences never enter BookDraft or a portable book.
struct NarrationDraftPreferences: Codable, Equatable {
    var voiceID = ""
    var defaultStyle: NarrationStyle = .natural
    var styleOverrides: [UUID: [Int: NarrationStyle]] = [:]
    var chapterTextHashes: [UUID: String] = [:]

    static func load(userID: String, draftID: UUID) -> Self {
        guard let data = try? Data(contentsOf: location(userID: userID, draftID: draftID)),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(userID: String, draftID: UUID) throws {
        let destination = Self.location(userID: userID, draftID: draftID)
        var directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(self).write(to: destination, options: [.atomic, .completeFileProtection])
    }

    static func removePrivateData(userID: String) {
        let owner = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        for directory in ["CloudNarrationDrafts", "CloudVoiceEnrollment"] {
            try? FileManager.default.removeItem(at: URL.cachesDirectory.appendingPathComponent("\(directory)/\(owner)", isDirectory: true))
        }
    }

    private static func location(userID: String, draftID: UUID) -> URL {
        let owner = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL.cachesDirectory.appendingPathComponent("CloudNarrationDrafts/\(owner)/\(draftID.uuidString).json")
    }
}
