import Foundation

/// The file-provider boundary can be replayed without a live iCloud account.
nonisolated struct LibraryDownloadProvider: Sendable {
    var readState: @Sendable (URL) throws -> LibraryDownloadState = Self.liveState
    var requestDownload: @Sendable (URL) throws -> Void = { try FileManager.default.startDownloadingUbiquitousItem(at: $0) }
    var timeout: Duration = .seconds(45)
    var pollInterval: Duration = .milliseconds(250)

    static func liveState(_ url: URL) throws -> LibraryDownloadState {
        // URL.resourceValues returns cached values, including an old iCloud
        // download status, on this actor's executor. Poll the backing store.
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey, .ubiquitousItemIsDownloadingKey,
            .fileSizeKey, .isRegularFileKey, .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey,
            .ubiquitousItemHasUnresolvedConflictsKey
        ])
        let status: String
        switch values.ubiquitousItemDownloadingStatus {
        case .current: status = "current"
        case .downloaded: status = "downloaded"
        case .notDownloaded: status = "not_downloaded"
        default: status = "unknown"
        }
        return LibraryDownloadState(isUbiquitousItem: values.isUbiquitousItem == true,
                                    status: status, isDownloading: values.ubiquitousItemIsDownloading == true,
                                    downloadError: values.ubiquitousItemDownloadingError,
                                    fileSize: values.fileSize, isRegularFile: values.isRegularFile,
                                    isUploaded: values.ubiquitousItemIsUploaded, isUploading: values.ubiquitousItemIsUploading,
                                    uploadError: values.ubiquitousItemUploadingError,
                                    hasConflicts: values.ubiquitousItemHasUnresolvedConflicts)
    }
}

nonisolated struct LibraryDownloadState: Sendable {
    var isUbiquitousItem: Bool
    var status: String
    var isDownloading: Bool = false
    var downloadError: (any Error)?
    var fileSize: Int?
    var isRegularFile: Bool?
    var isUploaded: Bool?
    var isUploading: Bool?
    var uploadError: (any Error)?
    var hasConflicts: Bool?
}
