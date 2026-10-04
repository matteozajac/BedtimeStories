import Foundation
import MZAppFoundation
import MZAppFoundationLocal

/// Render details at the local sink: Pulse's normal text copy omits metadata.
/// Feature messages and diagnostic issue codes remain short, structured events.
@MainActor final class AppDiagnosticLogger: AppLogging {
    private let sink: any AppLogging
    private let redaction: RedactionPolicy

    init(sink: any AppLogging, redaction: RedactionPolicy = .init()) {
        self.sink = sink
        self.redaction = redaction
    }

    func log(_ entry: LogEntry) {
        let entry = redaction.sanitize(entry)
        sink.log(LogEntry(AppDiagnosticText.render(entry), level: entry.level,
                          category: entry.category, metadata: entry.metadata,
                          error: entry.error, source: entry.source,
                          reportsToDiagnostics: entry.reportsToDiagnostics))
    }
}

nonisolated enum AppDiagnosticText {
    static func render(_ entry: LogEntry) -> String {
        var lines = [entry.message]
        let fields = entry.metadata.filter { $0.key != "verbosity" }.sorted { $0.key < $1.key }
        if !fields.isEmpty {
            lines.append("Context: " + fields.map { "\($0.key)=\($0.value.rendered)" }.joined(separator: "; "))
        }
        if entry.level == .error || entry.level == .warning {
            lines.append("Source: \(entry.source.file):\(entry.source.line) · \(entry.source.function)")
        }
        if let error = entry.error {
            for (index, cause) in error.causes.enumerated() {
                let explanation = cause.message ?? technicalExplanation(domain: cause.domain, code: cause.code)
                let label = index == 0 ? "Error" : "Cause \(index)"
                lines.append("\(label): \(cause.type) · \(cause.domain) (\(cause.code))" + (explanation.map { " — \($0)" } ?? ""))
            }
            if error.source != entry.source {
                lines.append("Captured: \(error.source.file):\(error.source.line) · \(error.source.function)")
            }
            lines.append("Stack (\(error.stack.origin.rawValue)):")
            lines.append(contentsOf: error.stack.symbols)
        }
        return lines.joined(separator: "\n")
    }

    /// These explanations depend only on public technical codes, never arbitrary
    /// localizedDescription/userInfo, which can contain story text or endpoints.
    static func technicalExplanation(domain: String, code: Int) -> String? {
        switch domain {
        case NSURLErrorDomain:
            switch code {
            case NSURLErrorTimedOut: "The connection timed out."
            case NSURLErrorNotConnectedToInternet: "The device is offline."
            case NSURLErrorNetworkConnectionLost: "The network connection was lost."
            case NSURLErrorCannotFindHost: "The server hostname could not be resolved."
            case NSURLErrorCannotConnectToHost: "The server could not be reached."
            case NSURLErrorSecureConnectionFailed: "The secure connection failed."
            case NSURLErrorServerCertificateUntrusted: "The server certificate is not trusted."
            case NSURLErrorCancelled: "The connection was cancelled."
            default: nil
            }
        case NSCocoaErrorDomain:
            switch code {
            case NSFileReadNoSuchFileError: "The requested file is missing."
            case NSFileReadNoPermissionError: "The file cannot be read because access was denied."
            case NSFileReadCorruptFileError: "The file is damaged or has an invalid format."
            case NSFileWriteNoPermissionError: "The file cannot be written because access was denied."
            case NSFileWriteOutOfSpaceError: "There is not enough free storage to write the file."
            case NSFileWriteVolumeReadOnlyError: "The destination storage is read-only."
            case NSFileLockingError: "The file is locked by another operation."
            case NSFileReadTooLargeError: "The file is too large to read."
            case NSFileReadUnknownStringEncodingError, NSFileReadInapplicableStringEncodingError: "The text file could not be decoded with the requested encoding."
            case NSFileWriteFileExistsError: "A file already occupies the save destination."
            case NSUbiquitousFileUnavailableError: "The requested iCloud file is unavailable."
            case NSUbiquitousFileNotUploadedDueToQuotaError: "iCloud storage quota prevented this file from being uploaded."
            case NSUbiquitousFileUbiquityServerNotAvailable: "The iCloud file server is unavailable."
            default: nil
            }
        case NSPOSIXErrorDomain:
            switch code {
            case 2: "The file or directory is missing."
            case 13: "Filesystem access was denied."
            case 20: "A required directory is a regular file."
            case 28: "The storage device has no free space."
            default: nil
            }
        case "NSFileProviderErrorDomain":
            switch code {
            case -1000: "The file provider requires account authentication."
            case -1001: "Another item already uses this filename in the provider."
            case -1002: "The file provider needs to refresh its synchronization state."
            case -1003: "The file provider account has insufficient storage quota."
            case -1004: "The file provider server could not be reached."
            case -1005: "The requested item no longer exists in the file provider."
            case -2005: "The file provider cannot synchronize this item; inspect its underlying cause."
            case -2007: "The item has local changes that have not synchronized."
            case -2011: "The file provider domain is disabled."
            case -2012: "The file provider domain is temporarily unavailable."
            default: nil
            }
        case "com.firebase.functions":
            switch code {
            case 3: "The server rejected an invalid argument."
            case 4: "The server operation exceeded its deadline."
            case 7: "The server denied permission for this operation."
            case 8: "The server quota or capacity was exhausted."
            case 9: "A required server precondition was not met."
            case 13: "The server reported an internal failure."
            case 14: "The server is temporarily unavailable."
            case 16: "The server could not authenticate the request."
            default: nil
            }
        default: nil
        }
    }
}

/// Same Foundation composition, with readable presentation confined to Pulse.
/// The diagnostic router still receives the original message, metadata and error.
@MainActor enum AppDiagnosticServices {
    static func make(configuration: AppConfiguration, schema: TelemetrySchema,
                     purchases: any PurchaseProviding = MockPurchases(),
                     defaults: UserDefaults = .standard, redaction: RedactionPolicy = .init(),
                     foundationDiagnostics: FoundationDiagnostics = .init(),
                     additionalAnalytics: [any AnalyticsEngine] = [],
                     additionalDiagnostics: [any DiagnosticsEngine] = []) -> AppServices {
        let logger = AppDiagnosticLogger(sink: AppPulseLogger(redaction: redaction), redaction: redaction)
        let engine = LocalTelemetryEngine(logger: logger)
        return AppServices(configuration: configuration,
                           telemetry: Telemetry(configuration: configuration, schema: schema,
                                                analytics: [engine] + additionalAnalytics,
                                                diagnostics: [engine] + additionalDiagnostics, redaction: redaction),
                           logger: logger, purchases: purchases,
                           developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults),
                           foundationDiagnostics: foundationDiagnostics)
    }
}
