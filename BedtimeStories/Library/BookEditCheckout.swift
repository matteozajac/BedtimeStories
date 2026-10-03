import Foundation
import MZAppFoundation

struct BookEditCheckout: Sendable {
    let book: LibraryBook
    let source: BookEditSource
}

/// Technical identities and monotonic timing shared across a book operation.
/// Filenames, titles, author details and story contents never enter these fields.
nonisolated struct BookOperationDiagnostics: Sendable {
    let operationID: String
    let bookID: UUID?
    let draftID: UUID?
    let started = ContinuousClock.now
    var phase: String
    var details: [String: TelemetryValue] = [:]

    init(operationID: String = UUID().uuidString, bookID: UUID? = nil,
         draftID: UUID? = nil, phase: String) {
        self.operationID = operationID; self.bookID = bookID
        self.draftID = draftID; self.phase = phase
    }

    var metadata: [String: TelemetryValue] {
        var values = details
        values["operation_id"] = .string(operationID)
        values["phase"] = .string(phase)
        values["elapsed_ms"] = .integer(Self.milliseconds(since: started))
        if let bookID { values["book_id"] = .string(bookID.uuidString) }
        if let draftID { values["draft_id"] = .string(draftID.uuidString) }
        return values
    }

    func failureEntry(_ message: String, error: any Error, category: String,
                      level: LogLevel = .error,
                      file: String = #fileID, function: String = #function, line: UInt = #line) -> LogEntry {
        let cancelled = ErrorSnapshot.isCancellation(error)
        var fields = metadata
        if cancelled { fields["cancelled"] = .bool(true); fields["verbosity"] = .string("trace") }
        return LogEntry(message, level: cancelled ? .debug : level, category: category, metadata: fields,
                        error: cancelled ? nil : ErrorSnapshot(error, file: file, function: function, line: line),
                        file: file, function: function, line: line)
    }

    static func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        let duration = instant.duration(to: .now).components
        return Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
    }

    static func assetKind(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "json": "manifest"
        case "md", "txt": "text"
        case "jpg", "jpeg", "png", "heic", "webp": "image"
        case "m4a", "mp3", "wav": "audio"
        case "bedtimestory": "archive"
        default: "other"
        }
    }
}

/// Preserve a provider's identity and reporting frames at the failing phase.
/// Presentation remains the original error; the diagnostic message is audited.
nonisolated struct BookOperationFailure: LocalizedError, LoggableError, UnderlyingErrorSnapshotProviding, Sendable {
    let presentation: String
    let phase: String
    let operationID: String
    let underlyingLogError: ErrorSnapshot?
    var errorDescription: String? { presentation }
    var logMessage: String { "Book operation failed during \(phase) (operation \(operationID))." }

    static func preserving(_ error: any Error, context: BookOperationDiagnostics,
                           file: String = #fileID, function: String = #function, line: UInt = #line) -> any Error {
        // Callers use these cases for conflict recovery and cancellation.
        if ErrorSnapshot.isCancellation(error) { return error }
        if case BookError.editConflict = error { return error }
        if case BookError.duplicate = error { return error }
        if error is BookOperationFailure { return error }
        return BookOperationFailure(presentation: error.localizedDescription, phase: context.phase,
                                    operationID: context.operationID,
                                    underlyingLogError: ErrorSnapshot(error, file: file, function: function, line: line))
    }
}
