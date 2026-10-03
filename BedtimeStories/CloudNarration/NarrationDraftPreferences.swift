import CryptoKit
import Foundation

/// Cloud-only preferences never enter BookDraft or a portable book.
struct NarrationDraftPreferences: Codable, Equatable {
    var voiceID = ""
    var defaultStyle: NarrationStyle = .natural
    var styleOverrides: [UUID: [Int: NarrationStyle]] = [:]
    var chapterTextHashes: [UUID: String] = [:]

    @MainActor static func load(userID: String, draftID: UUID) -> Self {
        do {
            let data = try Data(contentsOf: location(userID: userID, draftID: draftID))
            let value = try JSONDecoder().decode(Self.self, from: data)
            AppLog.trace("Narration draft preferences restored", category: "cloud_narration")
            return value
        } catch {
            if !isMissing(error) { AppLog.warning("Narration draft preferences restoration failed", error: error, category: "cloud_narration") }
            else { AppLog.trace("Narration draft preferences initialized", category: "cloud_narration") }
            return Self()
        }
    }

    @MainActor func save(userID: String, draftID: UUID) throws {
        let destination = Self.location(userID: userID, draftID: draftID)
        var directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(self).write(to: destination, options: [.atomic, .completeFileProtection])
        AppLog.trace("Narration draft preferences persisted", category: "cloud_narration")
    }

    @MainActor static func removePrivateData(userID: String) {
        let owner = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        for directory in ["CloudNarrationDrafts", "CloudVoiceEnrollment"] {
            do { try FileManager.default.removeItem(at: URL.cachesDirectory.appendingPathComponent("\(directory)/\(owner)", isDirectory: true)) }
            catch {
                if !isMissing(error) { AppLog.warning("Private narration preferences cleanup failed", error: error, category: "cloud_narration") }
            }
        }
        AppLog.trace("Private narration preferences cleanup completed", category: "cloud_narration")
    }

    private static func isMissing(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code)
    }

    private static func location(userID: String, draftID: UUID) -> URL {
        let owner = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL.cachesDirectory.appendingPathComponent("CloudNarrationDrafts/\(owner)/\(draftID.uuidString).json")
    }
}
