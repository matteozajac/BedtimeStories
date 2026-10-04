import AuthenticationServices
import SwiftUI

struct YourVoicesView: View {
    @Environment(OperationCenter.self) private var operations
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.colorScheme) private var colorScheme
    @State private var enrolling = false
    @State private var deletingVoice: VoiceProfile?
    @State private var deleteAccount = false
    @State private var message: String?
    @State private var preview = NarrationAudioPreview()
    @State private var previewJobID: String?
    @State private var previewVoiceID: String?
    @State private var auditionedVoiceID: String?
    @State private var previewLoading = false
    @State private var operation: Task<Void, Never>?
    @State private var active = false

    var body: some View {
        Form {
            CloudAccountView()
            if cloud.isConfigured, cloud.isEnabled, cloud.userID != nil {
                Section {
                    ForEach(cloud.voices.filter { $0.status != "deleted" }) { voice in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                VoiceAvatar()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(voice.displayName).storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
                                    VoiceStatusPill(status: voice.status)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Menu {
                                    Button("Delete Voice", systemImage: "trash", role: .destructive) { deletingVoice = voice }
                                        .disabled(cloud.isWorking || voice.status == "deleting")
                                } label: {
                                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44).contentShape(.rect)
                                }
                                .accessibilityLabel(String(localized: "Voice options"))
                            }
                            if voice.status == "processing" {
                                HStack(spacing: 12) {
                                    ProgressView().tint(Theme.glow)
                                    Text("Preparing your voice…").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            if voice.status == "failed" { Text("This voice could not be prepared. Delete it and record a new sample.").font(.footnote).foregroundStyle(.secondary) }
                            if voice.status == "awaitingApproval" {
                                Text("Listen to a preview, then choose whether to keep this voice.").font(.footnote).foregroundStyle(.secondary)
                            }
                            if voice.status == "ready" || voice.status == "awaitingApproval" {
                                let reviewing = voice.status == "awaitingApproval"
                                VStack(alignment: .leading, spacing: 10) {
                                    Button("Preview Voice", systemImage: "play.fill") { audition(voice) }
                                        .buttonStyle(.storySoft(fullWidth: reviewing))
                                        .disabled(cloud.isWorking || previewLoading || preview.loading)
                                    if reviewing {
                                        Button("Use This Voice", systemImage: "checkmark") {
                                            Task { do { try await cloud.approveVoice(profileID: voice.id) } catch { reportFailure("Voice approval failed", error: error) } }
                                        }
                                        .buttonStyle(.storyProminent(fullWidth: true))
                                        .disabled(auditionedVoiceID != voice.id || cloud.isWorking)
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    if cloud.voices.isEmpty {
                        Label {
                            Text("Save your voice once, then use it to narrate your stories.").foregroundStyle(.secondary)
                        } icon: { IconTile(systemName: "mic.fill", color: Theme.glow, size: 34) }
                        .padding(.vertical, 4)
                    }
                } header: { Text("Your Voices") } footer: {
                    Text("Record only your own voice. Your original samples stay private and are never included when you share a book.")
                }
                .listRowBackground(Theme.surface)
                Section {
                    Button("Add Your Voice", systemImage: "mic.badge.plus") {
                        AppLog.debug("Add private voice requested", category: "cloud_narration")
                        enrolling = true
                    }
                    .buttonStyle(.storyProminent(fullWidth: true))
                    .disabled(cloud.isWorking)
                    .accessibilityIdentifier("add-private-voice")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if previewLoading || preview.playingURL != nil {
                    Section {
                        if previewLoading {
                            HStack(spacing: 14) {
                                ProgressView().tint(Theme.glow)
                                Text("Creating your voice preview…").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if preview.playingURL != nil {
                            HStack(spacing: 14) {
                                Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                                    .symbolEffect(.variableColor.iterative).accessibilityHidden(true)
                                Button("Stop Preview", systemImage: "stop.fill", action: preview.stop)
                                    .buttonStyle(.storySoft).controlSize(.small)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                Section {
                    Button { cloud.signOut() } label: {
                        Label { Text("Sign Out").foregroundStyle(Theme.accent) } icon: { IconTile(systemName: "rectangle.portrait.and.arrow.right", size: 30) }
                    }
                    .disabled(cloud.isWorking)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Confirm with Apple before deleting your voice account.").font(.footnote).foregroundStyle(.secondary)
                        SignInWithAppleButton(.continue, onRequest: cloud.prepareAppleSignIn, onCompletion: cloud.handleAppleSignIn)
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 50).clipShape(.capsule).disabled(cloud.isWorking)
                            .accessibilityLabel("Confirm with Apple")
                    }
                    .padding(.vertical, 6)
                    Button(role: .destructive) { deleteAccount = true } label: {
                        Label { Text("Delete Voice Account") } icon: { IconTile(systemName: "trash.fill", color: Theme.recording, size: 30) }
                    }
                    .disabled(cloud.isWorking)
                } footer: { Text("Books you have already saved in your library remain available after signing out.") }
                .listRowBackground(Theme.surface)
            }
            if let message = message ?? cloud.message {
                Section { NoteCard(systemImage: "info.circle.fill", text: Text(message)) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .storyFormStyle()
        .navigationTitle("Your Voices").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $enrolling) { NavigationStack { VoiceEnrollmentView() }.operationFeedback() }
        .confirmationDialog("Delete this voice?", isPresented: Binding(get: { deletingVoice != nil }, set: { if !$0 { deletingVoice = nil } }), titleVisibility: .visible) {
            Button("Delete Voice", role: .destructive) {
                guard let voice = deletingVoice else { return }
                deletingVoice = nil
                Task { do { try await cloud.deleteVoice(profileID: voice.id) } catch { reportFailure("Voice deletion failed", error: error) } }
            }
        } message: { Text("Its samples and reusable voice will be removed. Narration already saved in your books remains.") }
        .confirmationDialog("Delete your voice account?", isPresented: $deleteAccount, titleVisibility: .visible) {
            Button("Delete Voice Account", role: .destructive) {
                Task { do { try await cloud.deleteAccount() } catch { reportFailure("Voice account deletion failed", error: error) } }
            }
        } message: { Text("Your saved voices, recordings, and cloud narration will be removed. Books already saved to your library remain.") }
        .onChange(of: cloud.jobs.map { $0.id + $0.state }) { _, _ in receivePreview() }
        .onChange(of: preview.playingURL) { _, url in if url != nil {
            auditionedVoiceID = previewVoiceID
            AppLog.debug("Private voice preview audition confirmed", category: "cloud_narration")
        } }
        .onChange(of: cloud.userID) { _, _ in operation?.cancel(); enrolling = false; deletingVoice = nil; message = nil; preview.stop(); previewJobID = nil; auditionedVoiceID = nil; previewLoading = false }
        .onAppear {
            AppLog.debug("Private voices screen opened", category: "cloud_narration", metadata: ["voice_count": .integer(cloud.voices.count), "signed_in": .bool(cloud.userID != nil)])
            active = true; receivePreview()
        }
        .onDisappear {
            AppLog.trace("Private voices screen closed", category: "cloud_narration", metadata: ["preview_pending": .bool(previewLoading)])
            active = false; operation?.cancel(); previewLoading = false; preview.stop()
        }
    }

    private func audition(_ voice: VoiceProfile) {
        guard let owner = cloud.userID, active else { return }
        preview.stop(); previewLoading = true; message = nil
        previewVoiceID = voice.id
        if let job = cloud.jobs.first(where: { $0.preview && $0.voiceProfileId == voice.id && $0.state == "ready" && $0.expiresAt > Date().timeIntervalSince1970 }) {
            previewJobID = job.id; receivePreview(); return
        }
        operations.start(kind: .voicePreview, title: voice.displayName, subtitle: String(localized: "Creating your voice preview…"), destination: .voices, ownerID: owner) { id in
            let jobID = try await cloud.startVoicePreview(profileID: voice.id, operationID: id)
            operations.attachRemote(id, remoteID: jobID)
            guard owner == cloud.userID else { return }
            if active { previewJobID = jobID; receivePreview() }
            cloud.refreshOperations()
        }
    }

    private func receivePreview() {
        guard active, let id = previewJobID, let job = cloud.jobs.first(where: { $0.id == id }) else { return }
        if job.state == "ready", job.expiresAt > Date().timeIntervalSince1970 {
            previewJobID = nil
            guard let owner = cloud.userID, active else { return }
            let voiceID = previewVoiceID
            operations.start(kind: .download, title: String(localized: "Voice Preview"), subtitle: String(localized: "Downloading narration…"), destination: .voices, ownerID: owner) { _ in
                defer { previewLoading = false }
                do {
                    let urls = try await cloud.download(job: job)
                    guard owner == cloud.userID, active, !Task.isCancelled else {
                        AppLog.trace("Private voice preview download result discarded after navigation or account change", category: "cloud_narration", metadata: ["cancelled": .bool(Task.isCancelled)])
                        return
                    }
                    guard let url = urls.values.first else { throw CloudNarrationFailure.invalidAudio }
                    AppLog.debug("Private voice preview ready to play", category: "cloud_narration")
                    previewVoiceID = voiceID; preview.toggle(url)
                } catch { reportFailure("Voice preview download failed", error: error); throw error }
            }
        } else if job.state == "failed" || job.state == "cancelled" || job.state == "expired" || job.expiresAt <= Date().timeIntervalSince1970 {
            AppLog.trace("Private voice preview stopped before audio became available", category: "cloud_narration", metadata: ["expired": .bool(job.expiresAt <= Date().timeIntervalSince1970 || job.state == "expired"), "worker_failed": .bool(job.state == "failed"), "cancelled": .bool(job.state == "cancelled")])
            previewJobID = nil; previewLoading = false
            message = job.state == "expired" || job.expiresAt <= Date().timeIntervalSince1970
                ? CloudNarrationFailure.expired.localizedDescription
                : String(localized: "This preview could not be created. Try again.")
        }
    }

    private func reportFailure(_ operation: String, error: any Error) {
        CloudNarrationDiagnostics.reportIfNeeded(operation, error: error)
        if !(error is CancellationError) { message = error.localizedDescription }
    }
}
