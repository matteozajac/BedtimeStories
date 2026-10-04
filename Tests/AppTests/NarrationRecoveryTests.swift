import Foundation
import Testing
@testable import BedtimeStories

@Suite
struct NarrationRecoveryTests {
    private let now = Date(timeIntervalSince1970: 1000)
    private let draftID = UUID()

    @Test func recoveryRequiresCurrentOwnerAndDoesNotTreatVoicePreviewDestinationAsDraft() {
        let ready = job(id: "ready", state: "ready", createdAt: 900)
        #expect(NarrationRecoveryTarget.select(destination: .narration(draftID), ownerID: "alice", currentOwnerID: nil, jobs: [ready], now: now) == nil)
        #expect(NarrationRecoveryTarget.select(destination: .narration(draftID), ownerID: "alice", currentOwnerID: "bob", jobs: [ready], now: now) == nil)
        var preview = ready; preview.preview = true
        #expect(NarrationRecoveryTarget.select(destination: .voices, ownerID: "alice", currentOwnerID: "alice", jobs: [preview], now: now) == nil)
        #expect(NarrationRecoveryTarget.select(destination: .narration(draftID), ownerID: "alice", currentOwnerID: "alice", jobs: [preview], now: now) == nil)
        #expect(NarrationRecoveryTarget.select(destination: .draft(draftID), ownerID: "alice", currentOwnerID: "alice", jobs: [preview], now: now)?.jobID == preview.id)
    }

    @Test func recoveryRejectsExpiredFailedDifferentDraftAndMissingAudioResults() {
        let expired = job(id: "expired", state: "ready", createdAt: 990, expiresAt: 999)
        let failed = job(id: "failed", state: "failed", createdAt: 990)
        let otherDraft = job(id: "other", state: "ready", createdAt: 990, draftID: UUID())
        var incomplete = job(id: "incomplete", state: "ready", createdAt: 990); incomplete.outputs = []
        #expect(NarrationRecoveryTarget.select(destination: .narration(draftID), ownerID: "alice", currentOwnerID: "alice", jobs: [expired, failed, otherDraft, incomplete], now: now) == nil)
    }

    @Test func selectionPrefersLatestPlayableResultAndAcceptsUUIDCaseAlias() throws {
        let older = job(id: "older", state: "ready", createdAt: 800)
        let latest = job(id: "latest", state: "ready", createdAt: 900)
        let active = job(id: "active", state: "processing", createdAt: 999)
        let target = try #require(NarrationRecoveryTarget.select(destination: .narration(draftID), ownerID: "alice", currentOwnerID: "alice", jobs: [active, older, latest], now: now))
        #expect(target.jobID == "latest")
        #expect(target.job(currentOwnerID: "alice", jobs: [latest], now: now) == latest)
        #expect(target.job(currentOwnerID: nil, jobs: [latest], now: now) == nil)
        #expect(target.job(currentOwnerID: "bob", jobs: [latest], now: now) == nil)
    }

    @Test func activeRecoveryKeepsSelectedJobWhenCompletionArrivesAndDoesNotSwitchJobs() throws {
        let active = job(id: "active", state: "processing", createdAt: 999)
        let target = try #require(NarrationRecoveryTarget.select(destination: .narration(draftID), ownerID: "alice", currentOwnerID: "alice", jobs: [active], now: now))
        let ready = job(id: "active", state: "ready", createdAt: 999)
        let different = job(id: "newer", state: "ready", createdAt: 1000)
        #expect(target.job(currentOwnerID: "alice", jobs: [different, ready], now: now) == ready)
        #expect(target.job(currentOwnerID: "alice", jobs: [different], now: now) == nil)
        #expect(target.job(currentOwnerID: "alice", jobs: [ready], now: Date(timeIntervalSince1970: 2000)) == nil)
    }

    @Test func onlyMissingFilesCanTriggerRecoveryInsteadOfRealReadFailure() {
        #expect(NarrationRecoveryTarget.isMissingDraft(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        #expect(!NarrationRecoveryTarget.isMissingDraft(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)))
        #expect(!NarrationRecoveryTarget.isMissingDraft(NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)))
        #expect(!NarrationRecoveryTarget.isMissingDraft(CancellationError()))
    }

    @Test func coldNotificationKeepsOwnedReceiptUntilItsCloudMetadataArrives() throws {
        var receipt = AppOperation(id: "receipt", kind: .narration, title: "Book", subtitle: "Ready",
                                   destination: .narration(draftID), ownerID: "alice")
        receipt.remoteID = "ready"; receipt.state = .ready; receipt.remoteExpiresAt = Date(timeIntervalSince1970: 2000)
        let target = try #require(NarrationRecoveryTarget.selectReceipt(destination: .narration(draftID), ownerID: "alice",
            currentOwnerID: "alice", operations: [receipt], now: now))
        #expect(target.job(currentOwnerID: "alice", jobs: [], now: now) == nil)
        let ready = job(id: "ready", state: "ready", createdAt: 900)
        #expect(target.job(currentOwnerID: "alice", jobs: [ready], now: now) == ready)
        #expect(NarrationRecoveryTarget.selectReceipt(destination: .narration(draftID), ownerID: "alice",
            currentOwnerID: "bob", operations: [receipt], now: now) == nil)
        receipt.state = .cancelled
        #expect(NarrationRecoveryTarget.selectReceipt(destination: .narration(draftID), ownerID: "alice",
            currentOwnerID: "alice", operations: [receipt], now: now) == nil)
        receipt.state = .ready; receipt.remoteExpiresAt = now
        #expect(NarrationRecoveryTarget.selectReceipt(destination: .narration(draftID), ownerID: "alice",
            currentOwnerID: "alice", operations: [receipt], now: now) == nil)
    }

    private func job(id: String, state: String, createdAt: Double, expiresAt: Double = 2000, draftID: UUID? = nil) -> NarrationJob {
        NarrationJob(id: id, state: state, progress: 0.5, draftId: (draftID ?? self.draftID).uuidString.lowercased(), snapshotHash: "hash", outputs: [
            NarrationOutput(chapterId: UUID().uuidString, path: "private-result", sha256: "hash", bytes: 100, duration: 10)
        ], createdAt: createdAt, expiresAt: expiresAt)
    }
}
