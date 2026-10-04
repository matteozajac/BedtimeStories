import Foundation

struct PendingVoiceUpload: Codable, Sendable {
    let operationID: String
    let ownerID: String
    let enrollment: VoiceEnrollment
    static var root: URL { URL.applicationSupportDirectory.appendingPathComponent("PendingVoiceUploads", isDirectory: true) }
    var directory: URL { Self.root.appendingPathComponent(operationID, isDirectory: true) }
    var referenceURL: URL { directory.appendingPathComponent("reference.wav") }
    var consentURL: URL { directory.appendingPathComponent("consent.wav") }

    func stage(reference: URL, consent: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (source, target) in [(reference, referenceURL), (consent, consentURL)] {
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("upload.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
    @MainActor func remove() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { AppLog.warning("Pending voice recordings could not be removed", error: error, category: "operations") }
    }
    @MainActor static func removePrivateData(ownerID: String, root: URL = PendingVoiceUpload.root) throws {
        let directories: [URL]
        do { directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) }
        catch {
            let value = error as NSError
            if value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code) { return }
            throw error
        }
        for directory in directories {
            let pending: Self
            do { pending = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("upload.json"))) }
            catch {
                AppLog.warning("Pending voice cleanup skipped an unreadable receipt", error: error, category: "operations")
                continue
            }
            guard pending.ownerID == ownerID else { continue }
            // Remove the enumerated directory rather than a path from decoded metadata.
            try FileManager.default.removeItem(at: directory)
        }
    }
    @MainActor func submit(cloud: CloudNarrationModel, center: OperationCenter) async throws {
        guard cloud.userID == ownerID else { throw CloudNarrationFailure.accountChanged }
        guard enrollment.expiresAt > Date().timeIntervalSince1970 else { remove(); throw CloudNarrationFailure.expired }
        center.trackRemoteSubmission(operationID, remoteID: enrollment.enrollmentId)
        let profileID = try await cloud.uploadEnrollment(enrollment: enrollment, referenceURL: referenceURL, consentURL: consentURL)
        center.attachRemote(operationID, remoteID: profileID)
        remove()
        cloud.refreshOperations()
    }
    @MainActor static func resume(cloud: CloudNarrationModel, center: OperationCenter) {
        guard let owner = cloud.userID else { return }
        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for directory in directories {
            do {
                let pending = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("upload.json")))
                guard pending.ownerID == owner else { continue }
                guard let operation = center.operations.first(where: { $0.id == pending.operationID }), operation.state != .cancelled else { pending.remove(); continue }
                if let voice = cloud.voices.first(where: { $0.id == pending.enrollment.enrollmentId }) {
                    center.attachRemote(pending.operationID, remoteID: voice.id)
                    pending.remove(); cloud.refreshOperations(); continue
                }
                guard cloud.hasLoadedVoices else { continue }
                if pending.enrollment.expiresAt <= Date().timeIntervalSince1970 {
                    pending.remove(); center.update(pending.operationID, state: .failed, message: CloudNarrationFailure.expired.localizedDescription); continue
                }
                center.run(id: pending.operationID) { _ in try await pending.submit(cloud: cloud, center: center) }
            } catch { AppLog.warning("Pending voice upload could not be resumed", error: error, category: "operations") }
        }
    }
}
