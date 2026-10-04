import Foundation
import Testing
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct OperationsTests {
    @Test func relaunchKeepsRemoteJobsAndMarksUnfinishedLocalWorkInterrupted() throws {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let local = center.begin(kind: .download, title: "Moon", subtitle: "Downloading", destination: .book(UUID()))
        center.update(local, state: .running, progress: 0.4)
        let remote = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .narration(UUID()), ownerID: "alice")
        center.attachRemote(remote, remoteID: "remote-job")
        center.update(remote, state: .running, progress: 0.6)
        let done = center.begin(kind: .saveBook, title: "Stars", subtitle: "Saving", destination: .book(UUID()))
        center.update(done, state: .ready, progress: 1)

        let restored = fixture.center()
        restored.changedOwner("alice")
        #expect(restored.operations.first { $0.id == local }?.state == .interrupted)
        #expect(restored.operations.first { $0.id == local }?.message != nil)
        #expect(restored.operations.first { $0.id == remote }?.state == .running)
        #expect(restored.operations.first { $0.id == remote }?.remoteID == "remote-job")
        #expect(restored.operations.first { $0.id == done }?.state == .ready)
        #expect(restored.activeOperations.map(\.id) == [remote])
        #expect(restored.banner == nil)
    }

    @Test func historyAndBannersStayScopedToCurrentAccount() {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let global = center.begin(kind: .importBook, title: "Local", subtitle: "Importing", destination: .importReview)
        let alice = center.begin(kind: .narration, title: "Alice", subtitle: "Creating", destination: .voices, ownerID: "alice")
        let bob = center.begin(kind: .narration, title: "Bob", subtitle: "Creating", destination: .voices, ownerID: "bob")
        center.update(global, state: .ready)
        center.update(alice, state: .ready)
        center.update(bob, state: .ready)
        #expect(center.banner?.id == alice)
        #expect(Set(center.visibleOperations.map(\.id)) == Set([global, alice]))
        center.requestedDestination = .voices
        center.changedOwner("bob")
        #expect(center.banner == nil && center.requestedDestination == nil)
        #expect(Set(center.visibleOperations.map(\.id)) == Set([global, bob]))
        center.clearHistory()
        #expect(center.operations.map(\.id) == [alice])
    }

    @Test func repeatedCloudAndPushCompletionDoNotPresentDuplicateBanner() {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .voices, ownerID: "alice")
        center.attachRemote(id, remoteID: "remote-job")
        center.update(id, state: .ready, progress: 1)
        #expect(center.banner?.id == id)
        center.dismissBanner()
        center.update(id, state: .ready, progress: 1)
        center.receivedNotification(operationID: "remote-job")
        center.receivedNotification(operationID: "remote-job")
        #expect(center.banner == nil)
    }

    @Test func alreadyPresentedCompletionStaysDismissedAfterRelaunch() {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .voices, ownerID: "alice")
        center.attachRemote(id, remoteID: "remote-job")
        center.update(id, state: .ready)
        center.dismissBanner()
        let restored = fixture.center()
        restored.changedOwner("alice")
        restored.receivedNotification(operationID: "remote-job")
        #expect(restored.banner == nil)
    }

    @Test func completedOperationIDDoesNotExecuteAgain() async throws {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        var executions = 0
        let id = center.start(kind: .shareBook, title: "Moon", subtitle: "Sharing", destination: .book(UUID()), id: "same-operation") { _ in executions += 1 }
        try await waitUntil { center.operations.first { $0.id == id }?.state == .ready }
        center.dismissBanner()
        center.start(kind: .shareBook, title: "Moon", subtitle: "Sharing", destination: .operations, id: id) { _ in executions += 1 }
        await settle()
        #expect(executions == 1)
        #expect(center.banner == nil)
        #expect(center.operations.count == 1)
    }

    @Test func navigationWaitsForDraftSaveAndUsesRemoteIDAlias() async throws {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let draftID = UUID()
        let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .narration(draftID), ownerID: "alice")
        center.attachRemote(id, remoteID: "remote-job")
        let gate = OperationGate()
        center.setNavigationPreparation(id: UUID()) { await gate.pause() }
        center.openOperation(id: "remote-job")
        await gate.waitForStart()
        #expect(center.requestedDestination == nil)
        gate.resume()
        try await waitUntil { center.requestedDestination != nil }
        #expect(center.requestedDestination == .narration(draftID))
    }

    @Test func accountChangesInvalidateNavigationEvenWhenOriginalAccountReturns() async {
        for returnToOriginal in [false, true] {
            let fixture = OperationFixture()
            defer { fixture.remove() }
            let center = fixture.center()
            center.changedOwner("alice")
            let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .voices, ownerID: "alice")
            let gate = OperationGate()
            center.setNavigationPreparation(id: UUID()) { await gate.pause() }
            center.openOperation(id: id)
            await gate.waitForStart()
            center.changedOwner("bob")
            if returnToOriginal { center.changedOwner("alice") }
            gate.resume()
            await settle()
            #expect(center.requestedDestination == nil)
        }
    }

    @Test func saveFailureBlocksNavigationAndCannotShowAnOldAccountError() async throws {
        for changeAccount in [false, true] {
            let fixture = OperationFixture()
            defer { fixture.remove() }
            let center = fixture.center()
            center.changedOwner("alice")
            let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .voices, ownerID: "alice")
            let gate = OperationGate()
            center.setNavigationPreparation(id: UUID()) {
                await gate.pause()
                throw NSError(domain: "DraftSaveTest", code: 1)
            }
            center.openOperation(id: id)
            await gate.waitForStart()
            if changeAccount { center.changedOwner("bob") }
            gate.resume()
            await settle()
            #expect(center.requestedDestination == nil)
            #expect((center.message == nil) == changeAccount)
        }
    }

    @Test func cancellationFromOperationsScreenStopsWorkWithoutCompletingIt() async throws {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        let gate = OperationGate()
        var reachedSuccess = false
        let id = center.start(kind: .download, title: "Moon", subtitle: "Downloading", destination: .book(UUID())) { _ in
            await gate.pause()
            try Task.checkCancellation()
            reachedSuccess = true
        }
        await gate.waitForStart()
        center.cancel(id: id)
        #expect(center.operations.first { $0.id == id }?.state == .cancelled)
        gate.resume()
        await settle()
        #expect(!reachedSuccess && center.banner == nil)
        #expect(fixture.center().operations.first { $0.id == id }?.state == .cancelled)
    }

    @Test func acceptedRemoteSubmissionWaitsForBackendCompletion() async throws {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let gate = OperationGate()
        let id = center.start(kind: .narration, title: "Rabbit", subtitle: "Submitting", destination: .voices, ownerID: "alice") { id in
            center.attachRemote(id, remoteID: "remote-job")
            await gate.pause()
        }
        await gate.waitForStart()
        gate.resume()
        await settle()
        #expect(center.operations.first { $0.id == id }?.state == .queued)
        #expect(center.banner == nil && center.activeOperations.count == 1)
        center.update(id, state: .ready, progress: 1)
        #expect(center.banner?.id == id && center.activeOperations.isEmpty)
    }

    @Test func atomicExternalSaveCannotBeCancelledAndKeepsTruthfulStateUntilCommit() {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        let id = center.begin(kind: .saveBook, title: "Moon", subtitle: "Saving", destination: .book(UUID()))
        center.update(id, state: .running)
        #expect(center.operations.first { $0.id == id }?.canCancel == true)
        center.beginExternal(id)
        #expect(center.operations.first { $0.id == id }?.canCancel == false)
        center.cancel(id: id)
        #expect(center.operations.first { $0.id == id }?.state == .running)
        center.endExternal(id, success: true)
        center.update(id, state: .ready)
        #expect(center.operations.first { $0.id == id }?.state == .ready)
        #expect(fixture.center().operations.first { $0.id == id }?.canCancel == false)
    }

    @Test func accountDeletionStopsOnlyThatOwnersStagedVoiceUploadTasks() async {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        let gate = OperationGate()
        var attached = false
        let alice = center.start(kind: .voiceEnrollment, title: "Alice", subtitle: "Uploading", destination: .voices, ownerID: "alice") { _ in
            await gate.pause()
            try Task.checkCancellation()
            attached = true
        }
        let bob = center.begin(kind: .voiceEnrollment, title: "Bob", subtitle: "Uploading", destination: .voices, ownerID: "bob")
        let remote = center.begin(kind: .voiceEnrollment, title: "Ready to train", subtitle: "Training", destination: .voices, ownerID: "alice")
        center.attachRemote(remote, remoteID: "profile")
        await gate.waitForStart()
        center.cancelPendingVoiceUploads(ownerID: "alice")
        gate.resume()
        await settle()
        #expect(!attached)
        #expect(center.operations.first { $0.id == alice }?.state == .cancelled)
        #expect(center.operations.first { $0.id == bob }?.state == .queued)
        #expect(center.operations.first { $0.id == remote }?.state == .cancelled)
    }

    @Test func accountDeletionRemovesOnlyOwnedPendingRecordingDirectories() throws {
        let root = URL.temporaryDirectory.appendingPathComponent("PendingVoiceCleanup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let enrollment = VoiceEnrollment(enrollmentId: "enrollment", expiresAt: 1, consentStatement: "Consent")
        for (id, owner) in [("alice-operation", "alice"), ("bob-operation", "bob")] {
            let directory = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pending = PendingVoiceUpload(operationID: id, ownerID: owner, enrollment: enrollment)
            try JSONEncoder().encode(pending).write(to: directory.appendingPathComponent("upload.json"))
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent("reference.wav"))
            try Data([4, 5, 6]).write(to: directory.appendingPathComponent("consent.wav"))
        }
        try PendingVoiceUpload.removePrivateData(ownerID: "alice", root: root)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("alice-operation").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("bob-operation/reference.wav").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("bob-operation/consent.wav").path))
        try PendingVoiceUpload.removePrivateData(ownerID: "alice", root: root)
        try PendingVoiceUpload.removePrivateData(ownerID: "alice", root: root.appendingPathComponent("missing"))
    }

    @Test func strictOperationLinksRejectAmbiguousPathsAndAccountOverrides() throws {
        let valid = try #require(URL(string: "bedtimestories://operation/job_A-01"))
        #expect(AppOperation.operationID(from: valid) == "job_A-01")
        let invalid = [
            "https://operation/job", "bedtimestories://other/job", "bedtimestories://operation/",
            "bedtimestories://operation/job/extra", "bedtimestories://operation//job",
            "bedtimestories://user@operation/job", "bedtimestories://user:pass@operation/job",
            "bedtimestories://operation:443/job", "bedtimestories://operation/job?owner=alice",
            "bedtimestories://operation/job#fragment", "bedtimestories://operation/%6Aob",
            "bedtimestories://operation/job%2Fextra", "bedtimestories://operation/%2E%2E",
            "bedtimestories://operation/" + String(repeating: "a", count: 129),
        ]
        for string in invalid {
            let url = try #require(URL(string: string))
            #expect(AppOperation.operationID(from: url) == nil)
        }
    }

    @Test func backgroundCompletionAndAnotherOwnersPushStayQuiet() {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.changedOwner("alice")
        center.sceneChanged(active: false)
        let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .voices, ownerID: "alice")
        center.attachRemote(id, remoteID: "remote-job")
        center.update(id, state: .ready)
        center.receivedNotification(operationID: "remote-job")
        #expect(center.banner == nil)
        center.changedOwner("bob")
        center.sceneChanged(active: true)
        center.receivedNotification(operationID: "remote-job")
        #expect(center.banner == nil)
    }

    @Test func coldNotificationWaitsForMatchingAccountAndRecoveredJob() async throws {
        let fixture = OperationFixture()
        defer { fixture.remove() }
        let center = fixture.center()
        center.routeNotification(operationID: "remote-job", ownerID: "alice")
        await settle()
        #expect(center.requestedDestination == nil)
        center.changedOwner("alice")
        let draftID = UUID()
        let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .narration(draftID), ownerID: "alice")
        center.attachRemote(id, remoteID: "remote-job")
        center.update(id, state: .ready)
        try await waitUntil { center.requestedDestination != nil }
        #expect(center.requestedDestination == .narration(draftID))
        center.consumeDestination()
        center.changedOwner("bob")
        center.routeNotification(operationID: "remote-job", ownerID: "alice")
        await settle()
        #expect(center.requestedDestination == nil)
    }

    @Test func cancellationReceiptSurvivesAcceptedResponseAndNormalizedRemoteID() async throws {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let requestID = UUID().uuidString
        let gate = OperationGate()
        let id = center.start(kind: .storyGeneration, title: "Rabbit", subtitle: "Submitting", destination: .draft(UUID()), ownerID: "alice") { id in
            center.trackRemoteSubmission(id, remoteID: requestID)
            await gate.pause()
            center.attachRemote(id, remoteID: requestID.lowercased())
        }
        await gate.waitForStart()
        center.cancel(id: id)
        gate.resume(); await settle()
        #expect(center.operations.first { $0.id == id }?.remoteID == requestID.lowercased())
        #expect(center.operations.first { $0.id == id }?.state == .cancelled)
        #expect(!center.shouldReconcileRemote(id, state: "processing"))
        #expect(!center.shouldReconcileRemote(id, state: "ready"))
        #expect(center.activeOperations.isEmpty && center.banner == nil)
    }

    @Test func remoteSnapshotBeforeCallableResponseMergesIntoOriginalBookDestination() {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let draftID = UUID()
        let original = center.begin(kind: .narration, title: "Rabbit", subtitle: "Submitting", destination: .narration(draftID), ownerID: "alice")
        let snapshot = center.begin(kind: .narration, title: "Book Narration", subtitle: "Creating", destination: .voices, ownerID: "alice")
        center.attachRemote(snapshot, remoteID: "remote-job")
        center.update(snapshot, state: .ready, progress: 1)
        center.attachRemote(original, remoteID: "remote-job")
        #expect(center.visibleOperations.count == 1)
        #expect(center.visibleOperations.first?.destination == .narration(draftID))
        #expect(center.visibleOperations.first?.state == .ready)
        #expect(center.banner?.id == original)
    }

    @Test func storyCompletionTapWaitsUntilDraftWasSaved() async throws {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let draftID = UUID()
        let id = center.begin(kind: .storyGeneration, title: "Rabbit", subtitle: "Writing", destination: .draft(draftID), ownerID: "alice")
        center.trackRemoteSubmission(id, remoteID: "remote-job")
        center.routeNotification(operationID: "remote-job", ownerID: "alice")
        await settle(); #expect(center.requestedDestination == nil)
        center.update(id, state: .ready, progress: 1)
        try await waitUntil { center.requestedDestination != nil }
        #expect(center.requestedDestination == .draft(draftID))
    }

    @Test func clearedRemoteHistoryKeepsPublishedBookReceiptForReplayedResult() async throws {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let draftID = UUID(); let bookID = UUID()
        let id = center.begin(kind: .storyGeneration, title: "Rabbit", subtitle: "Writing", destination: .draft(draftID), ownerID: "alice")
        center.attachRemote(id, remoteID: "remote-job"); center.update(id, state: .ready)
        center.markDraftPublished(draftID, bookID: bookID); center.clearHistory()
        #expect(center.visibleOperations.isEmpty)
        #expect(fixture.center().operations.first { $0.id == id }?.destination == .book(bookID))
        #expect(fixture.center().operations.first { $0.id == id }?.hiddenFromHistory == true)
        center.routeNotification(operationID: "remote-job", ownerID: "alice")
        try await waitUntil { center.requestedDestination != nil }
        #expect(center.requestedDestination == .book(bookID))
    }

    @Test func renewedOperationClearsOldFailureAndExpiredRemoteDoesNotWaitForever() {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let id = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .voices, ownerID: "alice")
        center.update(id, state: .failed, message: "Old error")
        center.update(id, state: .running)
        #expect(center.visibleOperations.first?.message == nil)
        center.attachRemote(id, remoteID: "remote-job")
        center.setRemoteExpiry(id, timestamp: Date().addingTimeInterval(-1).timeIntervalSince1970)
        center.expireRemoteOperations()
        #expect(center.visibleOperations.first?.state == .failed && center.activeOperations.isEmpty)
    }

    @Test func discardedDraftSubmissionCannotReturnThroughLateResponseOrPeerSnapshot() async throws {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let draftID = UUID(); let gate = OperationGate()
        let original = center.start(kind: .narration, title: "Rabbit", subtitle: "Submitting", destination: .narration(draftID), ownerID: "alice") { id in
            await gate.pause()
            center.attachRemote(id, remoteID: "late-job")
        }
        await gate.waitForStart()
        center.retireDraftOperations(draftID)
        center.clearHistory()
        #expect(center.operations.first { $0.id == original }?.state == .cancelled)
        let peer = center.begin(kind: .narration, title: "Recovered", subtitle: "Creating", destination: .narration(draftID), ownerID: "alice")
        center.attachRemote(peer, remoteID: "late-job"); center.update(peer, state: .ready)
        gate.resume(); await settle()
        #expect(center.operations.count == 1)
        #expect(center.operations.first?.id == original)
        #expect(center.operations.first?.state == .cancelled)
        #expect(center.operations.first?.hiddenFromHistory == true)
        #expect(center.operations.first?.destination == .operations)
        #expect(center.activeOperations.isEmpty && center.banner == nil)
        #expect(!center.shouldReconcileRemote(original, state: "ready"))
        center.routeNotification(operationID: "late-job", ownerID: "alice")
        try await waitUntil { center.requestedDestination != nil }
        #expect(center.requestedDestination == .operations)
    }

    @Test func draftDiscardAndRecoveryReceiptsStayScopedToTheCurrentAccount() {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let draftID = UUID()
        let alice = center.begin(kind: .narration, title: "Alice", subtitle: "Creating", destination: .narration(draftID), ownerID: "alice")
        let bob = center.begin(kind: .narration, title: "Bob", subtitle: "Creating", destination: .narration(draftID), ownerID: "bob")
        center.retireDraftOperations(draftID)
        #expect(center.operations.first { $0.id == alice }?.state == .cancelled)
        #expect(center.operations.first { $0.id == bob }?.state == .queued)
        center.changedOwner("bob")
        let recovered = center.begin(kind: .narration, title: "Bob", subtitle: "Recovered", destination: .narration(draftID), ownerID: "bob")
        #expect(center.operations.first { $0.id == recovered }?.state == .queued)
    }

    @Test func restoringDraftBaselineCancelsOldWorkButAllowsNewNarration() {
        let fixture = OperationFixture(); defer { fixture.remove() }
        let center = fixture.center(); center.changedOwner("alice")
        let draftID = UUID()
        let old = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .narration(draftID), ownerID: "alice")
        center.attachRemote(old, remoteID: "old-job")
        center.retireDraftOperations(draftID, draftDeleted: false)
        #expect(center.operations.first { $0.id == old }?.state == .cancelled)
        #expect(center.operations.first { $0.id == old }?.destination == .draft(draftID))
        let fresh = center.begin(kind: .narration, title: "Rabbit", subtitle: "Creating", destination: .narration(draftID), ownerID: "alice")
        #expect(center.operations.first { $0.id == fresh }?.state == .queued)
        #expect(center.operations.first { $0.id == fresh }?.destination == .narration(draftID))
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "OperationTestTimeout", code: 1) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private struct OperationFixture {
    let directory = URL.temporaryDirectory.appendingPathComponent("OperationsTests-" + UUID().uuidString)
    let defaults: UserDefaults
    let suite = "OperationsTests-" + UUID().uuidString
    init() { defaults = UserDefaults(suiteName: suite)! }
    func center() -> OperationCenter { OperationCenter(directory: directory, defaults: defaults, systemEnabled: false) }
    func remove() { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
}

@MainActor
private final class OperationGate {
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var isStarted = false
    func pause() async {
        await withCheckedContinuation { continuation in
            release = continuation
            isStarted = true
            started?.resume(); started = nil
        }
    }
    func waitForStart() async {
        guard !isStarted else { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { release?.resume(); release = nil }
}
