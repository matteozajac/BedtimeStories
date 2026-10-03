import CryptoKit
import Foundation
import MZAppFoundation

/// Each ID is generated for diagnostics alone and never identifies an account, book, or voice.
nonisolated struct CloudNarrationLogOperation: Sendable {
    let name: String
    let id = UUID().uuidString
    private let startedAt = ProcessInfo.processInfo.systemUptime

    var label: String {
        switch name {
        case "begin_voice_enrollment": "Voice enrollment creation"
        case "upload_voice_enrollment": "Voice enrollment recording upload"
        case "approve_voice": "Private voice approval"
        case "start_voice_preview": "Private voice preview creation"
        case "start_narration": "Book narration creation"
        case "cancel_narration": "Book narration cancellation"
        case "delete_voice": "Private voice deletion"
        case "delete_account": "Private voice account deletion"
        case "download_narration": "Generated narration download"
        default: "Cloud narration"
        }
    }

    var metadata: [String: TelemetryValue] {
        ["operation": .string(name), "diagnostic_operation_id": .string(id),
         "duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)]
    }
}

/// Changing the user-facing recovery must not discard the SDK's error identity or reporting stack.
nonisolated struct CloudNarrationFailureContext: LocalizedError, LoggableError, UnderlyingErrorSnapshotProviding {
    let presentation: any Error
    let underlyingLogError: ErrorSnapshot?
    var errorDescription: String? { presentation.localizedDescription }
    var logMessage: String {
        (presentation as? any LoggableError)?.logMessage ?? "Cloud narration failed; the underlying error evidence is preserved."
    }
}

/// A boundary owns the error report. Views and enclosing operations do not report it a second time.
nonisolated struct CloudNarrationReportedFailure: LocalizedError, LoggableError, UnderlyingErrorSnapshotProviding {
    let presentation: any Error
    let underlyingLogError: ErrorSnapshot?
    var errorDescription: String? { presentation.localizedDescription }
    var logMessage: String {
        (presentation as? any LoggableError)?.logMessage ?? "Cloud narration failed; the underlying error evidence is preserved."
    }
}

/// This reports a server state transition. Its stack describes the client report, not Gemini's throw site.
nonisolated struct CloudNarrationBackendFailure: Error, LoggableError {
    let code: String
    init(code: String = "unknown_backend_failure") { self.code = Self.safeCode(code) }

    var logMessage: String {
        switch code {
        case "provider_configuration": "The cloud worker could not use the configured Gemini provider."
        case "provider_access_unavailable": "Gemini rejected access to the provider service."
        case "provider_quota": "Gemini provider quota or billing limits prevented completion."
        case "provider_unavailable": "The Gemini provider service was unavailable."
        case "provider_rejected_recording_or_text": "Gemini rejected the voice recording or narration text."
        case "provider_voice_missing": "The reusable Gemini voice could not be found."
        case "provider_incomplete_audio", "invalid_provider_audio", "provider_audio_format": "Gemini returned incomplete or invalid audio."
        case "voice_creation_unconfirmed": "The worker could not confirm creation of the reusable Gemini voice."
        case "voice_reconciliation_incomplete": "The worker could not reconcile the reusable Gemini voice state."
        case "job_expired", "output_expired": "The worker job or generated output expired."
        default: "The cloud worker reported a terminal failure. Correlate the task key with worker logs for the original provider stack."
        }
    }

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
