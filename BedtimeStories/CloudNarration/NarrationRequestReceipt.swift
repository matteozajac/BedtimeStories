import CryptoKit
import Foundation

/// Persists only an unresolved request ID, so a timed-out submission can recover the same server job.
struct NarrationRequestReceipt: Codable {
    let requestID: String

    static func requestID(uid: String, draftID: UUID, snapshotHash: String, voiceID: String, preview: Bool) throws -> String {
        // Bump this version whenever wire segmentation/truncation changes.
        let identity = ["v1", draftID.uuidString, snapshotHash, voiceID, preview ? "preview" : "book"].joined(separator: "|")
        let key = digest(identity)
        var directory = directory(uid: uid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let url = directory.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(Self.self, from: data),
           UUID(uuidString: receipt.requestID) != nil { return receipt.requestID }
        let receipt = Self(requestID: UUID().uuidString)
        try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
        return receipt.requestID
    }

    static func confirm(uid: String, requestID: String) {
        confirm(uid: uid, requestIDs: [requestID])
    }

    static func confirm(uid: String, requestIDs: Set<String>) {
        guard !requestIDs.isEmpty else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(uid: uid), includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let receipt = try? JSONDecoder().decode(Self.self, from: data), requestIDs.contains(receipt.requestID) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func removePrivateData(uid: String) { try? FileManager.default.removeItem(at: directory(uid: uid)) }

    private static func directory(uid: String) -> URL {
        URL.cachesDirectory.appendingPathComponent("CloudNarrationRequests/" + digest(uid), isDirectory: true)
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
