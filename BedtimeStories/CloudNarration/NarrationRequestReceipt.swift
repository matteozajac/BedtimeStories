import CryptoKit
import Foundation

/// Persists only an unresolved request ID, so a timed-out submission can recover the same server job.
struct NarrationRequestReceipt: Codable {
    let requestID: String

    @MainActor static func requestID(uid: String, draftID: UUID, snapshotHash: String, voiceID: String, preview: Bool) throws -> String {
        AppLog.trace("Narration request recovery lookup started", category: "cloud_narration", metadata: ["preview": .bool(preview)])
        // Bump this version whenever wire segmentation/truncation changes.
        let identity = ["v1", draftID.uuidString, snapshotHash, voiceID, preview ? "preview" : "book"].joined(separator: "|")
        let key = digest(identity)
        var directory = directory(uid: uid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let url = directory.appendingPathComponent(key + ".json")
        do {
            let data = try Data(contentsOf: url)
            let receipt = try JSONDecoder().decode(Self.self, from: data)
            if UUID(uuidString: receipt.requestID) != nil {
                AppLog.debug("Narration unresolved request reused", category: "cloud_narration")
                return receipt.requestID
            }
            AppLog.warning("Narration request recovery identity invalid", error: CloudNarrationFailure.invalidResponse, category: "cloud_narration")
        } catch {
            if !isMissing(error) { AppLog.warning("Narration request recovery unavailable", error: error, category: "cloud_narration") }
        }
        let receipt = Self(requestID: UUID().uuidString)
        try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
        AppLog.trace("Narration unresolved request persisted", category: "cloud_narration")
        return receipt.requestID
    }

    @MainActor static func confirm(uid: String, requestID: String) {
        confirm(uid: uid, requestIDs: [requestID])
    }

    @MainActor static func confirm(uid: String, requestIDs: Set<String>) {
        guard !requestIDs.isEmpty else { return }
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory(uid: uid), includingPropertiesForKeys: nil) }
        catch {
            if !isMissing(error) { AppLog.warning("Narration request confirmation lookup failed", error: error, category: "cloud_narration") }
            return
        }
        var removedCount = 0
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let receipt = try JSONDecoder().decode(Self.self, from: data)
                guard requestIDs.contains(receipt.requestID) else { continue }
                try FileManager.default.removeItem(at: file)
                removedCount += 1
            } catch {
                if !isMissing(error) { AppLog.warning("Narration request confirmation failed", error: error, category: "cloud_narration") }
            }
        }
        AppLog.trace("Narration request confirmation completed", category: "cloud_narration", metadata: ["confirmed_count": .integer(removedCount)])
    }

    @MainActor static func removePrivateData(uid: String) {
        do {
            try FileManager.default.removeItem(at: directory(uid: uid))
            AppLog.trace("Private narration recovery data removed", category: "cloud_narration")
        } catch {
            if !isMissing(error) { AppLog.warning("Private narration recovery cleanup failed", error: error, category: "cloud_narration") }
        }
    }

    private static func isMissing(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code)
    }

    private static func directory(uid: String) -> URL {
        URL.cachesDirectory.appendingPathComponent("CloudNarrationRequests/" + digest(uid), isDirectory: true)
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
