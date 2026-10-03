import Foundation
import MZAppFoundation

@MainActor
final class CloudLibraryObserver: NSObject {
    private let query = NSMetadataQuery()
    private let root: URL
    private let changed: @MainActor ([URL]) -> Void
    private let logger: any AppLogging
    private var previousFolders = Set<URL>()

    init(root: URL, logger: any AppLogging = AppLog.logger, changed: @escaping @MainActor ([URL]) -> Void) {
        self.root = root
        self.changed = changed
        self.logger = logger
        super.init()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "book.json")
        query.notificationBatchingInterval = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updated(_:)), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(updated(_:)), name: .NSMetadataQueryDidUpdate, object: query)
        if query.start() { logger.trace("iCloud library observation started", category: "library") }
        else { logger.warning("iCloud library observation could not start", category: "library") }
    }

    @objc private func updated(_ notification: Notification) {
        query.disableUpdates()
        let prefix = root.standardizedFileURL.path + "/"
        let folders = (query.results as? [NSMetadataItem] ?? []).compactMap { item -> URL? in
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.standardizedFileURL.path.hasPrefix(prefix) else { return nil }
            return url.deletingLastPathComponent()
        }
        query.enableUpdates()
        let current = Set(folders)
        let initial = notification.name == .NSMetadataQueryDidFinishGathering
        func relevantUpdateCount(_ key: String) -> Int {
            (notification.userInfo?[key] as? [NSMetadataItem] ?? []).filter { item in
                guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return false }
                return url.standardizedFileURL.path.hasPrefix(prefix)
            }.count
        }
        let changedItems = relevantUpdateCount(NSMetadataQueryUpdateChangedItemsKey)
        let addedItems = relevantUpdateCount(NSMetadataQueryUpdateAddedItemsKey)
        let removedItems = relevantUpdateCount(NSMetadataQueryUpdateRemovedItemsKey)
        if initial || current != previousFolders || changedItems + addedItems + removedItems > 0 {
            logger.trace("iCloud library metadata received", category: "library", metadata: [
                "trigger": .string(initial ? "initial_gathering" : "metadata_update"),
                "query_result_count": .integer(query.resultCount), "library_folder_count": .integer(current.count),
                "added_folder_count": .integer(current.subtracting(previousFolders).count),
                "removed_folder_count": .integer(previousFolders.subtracting(current).count),
                "changed_item_count": .integer(changedItems), "added_item_count": .integer(addedItems),
                "removed_item_count": .integer(removedItems)
            ])
        }
        previousFolders = current
        changed(folders)
    }

    func stop() {
        logger.trace("iCloud library observation stopped", category: "library", metadata: ["library_folder_count": .integer(previousFolders.count)])
        query.stop(); NotificationCenter.default.removeObserver(self)
    }
    isolated deinit { query.stop(); NotificationCenter.default.removeObserver(self) }
}
