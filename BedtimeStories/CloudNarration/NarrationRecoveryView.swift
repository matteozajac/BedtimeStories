import Foundation
import SwiftUI

/// A missing draft can expose its owned audio, never an inferred editing copy.
struct NarrationRecoveryTarget: Identifiable, Equatable, Sendable {
    let ownerID: String
    let draftID: UUID
    let jobID: String
    var id: String { ownerID + ":" + jobID }

    static func select(destination: OperationDestination, ownerID: String, currentOwnerID: String?,
                       jobs: [NarrationJob], now: Date = Date()) -> Self? {
        guard currentOwnerID == ownerID else { return nil }
        let draftID: UUID
        let requiresFullNarration: Bool
        switch destination {
        case .draft(let id): draftID = id; requiresFullNarration = false
        case .narration(let id): draftID = id; requiresFullNarration = true
        default: return nil
        }
        let candidates = jobs.filter {
            $0.draftId.caseInsensitiveCompare(draftID.uuidString) == .orderedSame &&
            (!requiresFullNarration || !$0.preview) && usable($0, now: now)
        }
        guard let selected = candidates.sorted(by: {
            if ($0.state == "ready") != ($1.state == "ready") { return $0.state == "ready" }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }).first else { return nil }
        return Self(ownerID: ownerID, draftID: draftID, jobID: selected.id)
    }

    /// A cold notification can arrive before the first Firestore snapshot.
    /// Retain the known owned job instead of permanently discarding its route.
    static func selectReceipt(destination: OperationDestination, ownerID: String, currentOwnerID: String?,
                              operations: [AppOperation], now: Date = Date()) -> Self? {
        guard currentOwnerID == ownerID else { return nil }
        let draftID: UUID
        switch destination {
        case .draft(let id), .narration(let id): draftID = id
        default: return nil
        }
        guard let receipt = operations.filter({
            $0.ownerID == ownerID && $0.destination == destination &&
            ($0.kind == .narration || $0.kind == .voicePreview) &&
            ($0.isActive || $0.state == .ready) && $0.remoteID != nil &&
            ($0.remoteExpiresAt.map { $0 > now } ?? true)
        }).max(by: { $0.createdAt < $1.createdAt }), let jobID = receipt.remoteID else { return nil }
        return Self(ownerID: ownerID, draftID: draftID, jobID: jobID)
    }

    func job(currentOwnerID: String?, jobs: [NarrationJob], now: Date = Date()) -> NarrationJob? {
        guard currentOwnerID == ownerID else { return nil }
        return jobs.first { $0.id == jobID && $0.draftId.caseInsensitiveCompare(draftID.uuidString) == .orderedSame && Self.usable($0, now: now) }
    }

    static func isMissingDraft(_ error: any Error) -> Bool {
        let value = error as NSError
        return value.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(value.code)
    }

    private static func usable(_ job: NarrationJob, now: Date) -> Bool {
        guard job.expiresAt > now.timeIntervalSince1970 else { return false }
        return job.state == "queued" || job.state == "processing" || (job.state == "ready" && !job.outputs.isEmpty)
    }
}

struct NarrationRecoveryView: View {
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(OperationCenter.self) private var operations
    @Environment(\.dismiss) private var dismiss
    let target: NarrationRecoveryTarget
    @State private var preview = NarrationAudioPreview()
    @State private var downloaded: [UUID: URL] = [:]
    @State private var downloading = false
    @State private var active = false
    @State private var now = Date()
    @State private var message: String?

    private var job: NarrationJob? { target.job(currentOwnerID: cloud.userID, jobs: cloud.jobs, now: now) }

    var body: some View {
        List {
            Section {
                Label("The draft for this narration was removed.", systemImage: "waveform")
                    .storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
                Text("You can listen to the recordings here. To add narration to a book, open it from your library and create it again.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .listRowBackground(Theme.surface)
            if let job {
                if job.state == "ready" {
                    if downloading {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView().tint(Theme.accent)
                                Text("Downloading narration…").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.listRowBackground(Theme.surface)
                    }
                    Section("Available Recordings") {
                        ForEach(Array(job.outputs.enumerated()), id: \.element.chapterId) { index, output in
                            recordingRow(output, index: index, job: job)
                        }
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    Section {
                        ProgressView(value: min(1, max(0, job.progress))) {
                            Text(job.state == "queued" ? "Waiting to create narration…" : "Creating narration…")
                        }.tint(Theme.glow)
                        Text("This narration is still being created. You can leave this screen and return from Ongoing Operations.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Theme.surface)
                }
            } else {
                Section {
                    Text("This recording is no longer available. Open the book from your library and create narration again.")
                        .foregroundStyle(.secondary)
                }.listRowBackground(Theme.surface)
            }
            Section {
                Button("View Ongoing Operations", systemImage: "clock.arrow.circlepath") {
                    operations.requestedDestination = .operations
                }.foregroundStyle(Theme.accent)
            }.listRowBackground(Theme.surface)
        }
        .storyFormStyle()
        .navigationTitle("Narration Recordings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { active = true; now = Date() }
        .onDisappear { active = false; preview.stop() }
        .onChange(of: cloud.userID) { _, owner in
            guard owner != target.ownerID else { return }
            preview.stop(); downloaded = [:]; dismiss()
        }
        .onChange(of: cloud.jobs) { _, _ in
            now = Date()
            if job?.state != "ready" { preview.stop(); downloaded = [:] }
        }
        .task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(30))
                    now = Date()
                    if job == nil { preview.stop(); downloaded = [:] }
                }
            } catch { }
        }
        .alert("Unable to complete", isPresented: Binding(get: { message != nil || preview.message != nil }, set: { if !$0 { message = nil; preview.message = nil } })) { } message: {
            Text(message ?? preview.message ?? "")
        }
        .accessibilityIdentifier("narration-recovery")
    }

    private func recordingRow(_ output: NarrationOutput, index: Int, job: NarrationJob) -> some View {
        let chapterID = UUID(uuidString: output.chapterId)
        let url = chapterID.flatMap { downloaded[$0] }
        let playing = url != nil && preview.playingURL == url
        return HStack(spacing: 14) {
            IconTile(systemName: "waveform", color: Theme.accent, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Chapter \(index + 1)").storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
                Text(Duration.seconds(output.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(playing ? "Stop Listening" : "Listen", systemImage: playing ? "stop.fill" : "play.fill") {
                if playing { preview.stop() }
                else if let chapterID { listen(chapterID: chapterID, job: job) }
            }
            .buttonStyle(.storySoft(fullWidth: false))
            .disabled(chapterID == nil || downloading || preview.loading)
        }
    }

    private func listen(chapterID: UUID, job: NarrationJob) {
        guard active, cloud.userID == target.ownerID, job.expiresAt > Date().timeIntervalSince1970 else { return }
        if let url = downloaded[chapterID] { preview.toggle(url); return }
        downloading = true; message = nil
        let generation = operations.ownerGeneration
        operations.start(kind: .download, title: String(localized: "Narration Recordings"), subtitle: String(localized: "Downloading narration…"), destination: .operations, ownerID: target.ownerID) { _ in
            defer { downloading = false }
            do {
                let urls = try await cloud.download(job: job)
                guard generation == operations.ownerGeneration, cloud.userID == target.ownerID, !Task.isCancelled else { throw CancellationError() }
                guard let url = urls[chapterID] else { throw CloudNarrationFailure.invalidAudio }
                guard active, target.job(currentOwnerID: cloud.userID, jobs: cloud.jobs)?.id == job.id else { return }
                downloaded = urls
                preview.toggle(url)
            } catch {
                CloudNarrationDiagnostics.reportIfNeeded("Recovered narration download failed", error: error)
                if active, generation == operations.ownerGeneration, !(error is CancellationError) {
                    message = String(localized: "Your narration could not be opened. Try again.")
                }
                throw error
            }
        }
    }
}
