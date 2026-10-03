import CryptoKit
import Foundation
import MZAppFoundation

/// Each ID is generated for diagnostics alone and never identifies an account, book, or voice.
nonisolated struct CloudNarrationLogOperation: Sendable {
    let name: String
    let id = UUID().uuidString
    private let startedAt = ProcessInfo.processInfo.systemUptime

    var metadata: [String: TelemetryValue] {
        ["operation": .string(name), "diagnostic_operation_id": .string(id),
         "duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)]
    }
}

/// Changing the user-facing recovery must not discard the SDK's error identity or reporting stack.
nonisolated struct CloudNarrationFailureContext: LocalizedError, UnderlyingErrorSnapshotProviding {
    let presentation: any Error
    let underlyingLogError: ErrorSnapshot?
    var errorDescription: String? { presentation.localizedDescription }
}

/// A boundary owns the error report. Views and enclosing operations do not report it a second time.
nonisolated struct CloudNarrationReportedFailure: LocalizedError, UnderlyingErrorSnapshotProviding {
    let presentation: any Error
    let underlyingLogError: ErrorSnapshot?
    var errorDescription: String? { presentation.localizedDescription }
}

/// This reports a server state transition. Its stack describes the client report, not Gemini's throw site.
nonisolated struct CloudNarrationBackendFailure: Error, LoggableError {
    var logMessage: String { "The cloud worker reported a terminal failure. Provider error evidence is recorded by the worker." }

    static func safeCode(_ code: String?) -> String {
        let known: Set<String> = [
            "provider_rejected_recording_or_text", "provider_configuration", "provider_access_unavailable",
            "provider_voice_missing", "provider_quota", "provider_unavailable", "provider_failed",
            "invalid_provider_response", "provider_incomplete_audio", "provider_audio_format", "invalid_provider_audio",
            "voice_reconciliation_incomplete", "consent_required", "voice_reconciliation_required",
            "voice_creation_unconfirmed", "voice_deletion_unconfirmed", "lease_busy", "lease_lost", "job_expired",
            "invalid_snapshot", "snapshot_too_large", "job_continuing", "invalid_audio", "invalid_audio_duration",
            "truncated_audio", "empty_audio", "encoding_failed", "invalid_recording_path", "invalid_recording_size",
            "invalid_envelope", "invalid_checkpoint", "ownership_mismatch", "internal_retry", "output_expired",
            "voice_deleted", "cancelled", "chapter_too_long", "empty_text", "invalid_identifier", "invalid_task",
            "invalid_style", "invalid_provider_voice", "envelope_owner_mismatch", "deletion_not_requested",
            "deletion_waiting_for_worker", "deletion_waiting_for_upload"
        ]
        guard let code, known.contains(code) else { return "unknown_backend_failure" }
        return code
    }
}

@MainActor
enum CloudNarrationDiagnostics {
    nonisolated static func taskKey(kind: String, uid: String, id: String) -> String {
        SHA256.hash(data: Data("\(kind):\(uid):\(id)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func reportIfNeeded(_ message: String, error: any Error,
                               metadata: [String: TelemetryValue] = [:],
                               file: String = #fileID, function: String = #function, line: UInt = #line) {
        guard !(error is CloudNarrationReportedFailure) else { return }
        if ErrorSnapshot.isCancellation(error) {
            AppLog.trace("Cloud narration operation cancelled", category: "cloud_narration", metadata: metadata,
                         file: file, function: function, line: line)
        } else {
            AppLog.error(message, error: error, category: "cloud_narration", metadata: metadata,
                         file: file, function: function, line: line)
        }
    }
}
