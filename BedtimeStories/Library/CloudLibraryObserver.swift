import Foundation
import MZAppFoundation

@MainActor
final class CloudLibraryObserver: NSObject {
    private let query = NSMetadataQuery()
    private let root: URL
    private let changed: @MainActor ([URL]) -> Void
    private let logger: any AppLogging

    init(root: URL, logger: any AppLogging = AppLog.logger, changed: @escaping @MainActor ([URL]) -> Void) {
        self.root = root
        self.changed = changed
        self.logger = logger
        super.init()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "book.json")
        query.notificationBatchingInterval = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updated), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(updated), name: .NSMetadataQueryDidUpdate, object: query)
        if query.start() { logger.trace("iCloud library observation started", category: "library") }
        else { logger.warning("iCloud library observation could not start", category: "library") }
    }

    @objc private func updated() {
        query.disableUpdates()
        let prefix = root.standardizedFileURL.path + "/"
        let folders = (query.results as? [NSMetadataItem] ?? []).compactMap { item -> URL? in
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.standardizedFileURL.path.hasPrefix(prefix) else { return nil }
            return url.deletingLastPathComponent()
        }
        query.enableUpdates()
        changed(folders)
    }

    func stop() { query.stop(); NotificationCenter.default.removeObserver(self) }
    isolated deinit { query.stop(); NotificationCenter.default.removeObserver(self) }
}
