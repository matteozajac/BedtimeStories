import CryptoKit
import Foundation

actor DefaultLibraryStorage {
    static let containerIdentifier = "iCloud.com.matteozajac.bedtimestories"
    let localRoot: URL
    private let container: @Sendable () -> URL?
    private let identity: @Sendable () -> String

    init(localRoot: URL = URL.documentsDirectory.appendingPathComponent("Books", isDirectory: true),
         container: @escaping @Sendable () -> URL? = { FileManager.default.url(forUbiquityContainerIdentifier: DefaultLibraryStorage.containerIdentifier) },
         identity: @escaping @Sendable () -> String = {
             guard let token = FileManager.default.ubiquityIdentityToken else { return "icloud" }
             do {
                 let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
                 return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
             } catch {
                 var log = FeatureLogBuffer(destination: nil)
                 log.warning("iCloud account cache identity could not be prepared", error: error, category: "library", metadata: ["recovery": .string("default_icloud_namespace")])
                 return "icloud"
             }
         }) {
        self.localRoot = localRoot
        self.container = container
        self.identity = identity
    }

    // Actor isolation keeps the potentially blocking container lookup and file coordination off the main thread.
    func prepare(logDestination: FeatureLogDestination? = nil) throws -> LibraryLocation {
        var log = FeatureLogBuffer(destination: logDestination)
        let operationID = UUID().uuidString
        let startedAt = ProcessInfo.processInfo.systemUptime
        log.trace("Default library container lookup started", category: "library", metadata: ["operation_id": .string(operationID)])
        let location: LibraryLocation
        if let container = container() {
            location = LibraryLocation(root: container.appendingPathComponent("Documents/Books", isDirectory: true), isCloud: true, account: identity())
        } else {
            location = LibraryLocation(root: localRoot, isCloud: false, account: "device")
        }
        log.trace("Default library storage selected", category: "library", metadata: [
            "operation_id": .string(operationID), "icloud": .bool(location.isCloud),
            "elapsed_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        ])
        var coordinationError: NSError?
        var creationError: Error?
        var created = false
        log.trace("Default library folder coordination started", category: "library", metadata: ["operation_id": .string(operationID), "icloud": .bool(location.isCloud)])
        NSFileCoordinator().coordinate(writingItemAt: location.root, options: .forMerging, error: &coordinationError) { url in
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); created = true }
            catch { creationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let creationError { throw creationError }
        guard created else { throw BookError.unavailable("The file provider did not grant access.") }
        log.trace("Default library folder prepared", category: "library", metadata: [
            "operation_id": .string(operationID), "icloud": .bool(location.isCloud),
            "elapsed_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        ])
        return location
    }
}
