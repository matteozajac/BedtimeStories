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
             guard let token = FileManager.default.ubiquityIdentityToken,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) else { return "icloud" }
             return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
         }) {
        self.localRoot = localRoot
        self.container = container
        self.identity = identity
    }

    // Actor isolation keeps the potentially blocking container lookup and file coordination off the main thread.
    func prepare() throws -> LibraryLocation {
        let location: LibraryLocation
        if let container = container() {
            location = LibraryLocation(root: container.appendingPathComponent("Documents/Books", isDirectory: true), isCloud: true, account: identity())
        } else {
            location = LibraryLocation(root: localRoot, isCloud: false, account: "device")
        }
        var coordinationError: NSError?
        var creationError: Error?
        var created = false
        NSFileCoordinator().coordinate(writingItemAt: location.root, options: .forMerging, error: &coordinationError) { url in
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); created = true }
            catch { creationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let creationError { throw creationError }
        guard created else { throw BookError.unavailable("The file provider did not grant access.") }
        return location
    }
}
