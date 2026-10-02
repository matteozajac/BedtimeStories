import AuthenticationServices
import SwiftUI

struct YourVoicesView: View {
    @Environment(CloudNarrationModel.self) private var cloud
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(voice.displayName, systemImage: "person.wave.2")
                                Spacer()
                                Text(status(voice.status)).font(.caption).foregroundStyle(.secondary)
                            }
                            if voice.status == "processing" { ProgressView("Preparing your voice…") }
                            if voice.status == "failed" { Text("This voice could not be prepared. Delete it and record a new sample.").font(.footnote).foregroundStyle(.secondary) }
                            if voice.status == "ready" || voice.status == "awaitingApproval" {
                                Button("Preview Voice", systemImage: "play.circle") { audition(voice) }
                                    .disabled(cloud.isWorking || previewLoading || preview.loading)
                            }
                            if voice.status == "awaitingApproval" {
                                Text("Listen to a preview, then choose whether to keep this voice.").font(.footnote).foregroundStyle(.secondary)
                                Button("Use This Voice", systemImage: "checkmark.circle") {
                                    Task { do { try await cloud.approveVoice(profileID: voice.id) } catch { message = error.localizedDescription } }
                                }.disabled(auditionedVoiceID != voice.id || cloud.isWorking)
                            }
                            Button("Delete Voice", systemImage: "trash", role: .destructive) { deletingVoice = voice }
                                .disabled(cloud.isWorking || voice.status == "deleting")
                        }.padding(.vertical, 4)
                    }
                    if cloud.voices.isEmpty { Text("Save your voice once, then use it to narrate your stories.").foregroundStyle(.secondary) }
                    Button("Add Your Voice", systemImage: "mic.badge.plus") { enrolling = true }
                        .disabled(cloud.isWorking)
                        .accessibilityIdentifier("add-private-voice")
                } header: { Text("Your Voices") } footer: {
                    Text("Record only your own voice. Your original samples stay private and are never included when you share a book.")
                }
                if previewLoading { ProgressView("Creating your voice preview…") }
                if preview.playingURL != nil { Button("Stop Preview", systemImage: "stop.circle", action: preview.stop) }
                Section {
                    Button("Sign Out") { cloud.signOut() }.disabled(cloud.isWorking)
                    Text("Confirm with Apple before deleting your voice account.").font(.footnote).foregroundStyle(.secondary)
                    SignInWithAppleButton(.continue, onRequest: cloud.prepareAppleSignIn, onCompletion: cloud.handleAppleSignIn)
                        .frame(minHeight: 50).clipShape(.rect(cornerRadius: 10)).disabled(cloud.isWorking)
                        .accessibilityLabel("Confirm with Apple")
                    Button("Delete Voice Account", role: .destructive) { deleteAccount = true }.disabled(cloud.isWorking)
                } footer: { Text("Books you have already saved in your library remain available after signing out.") }
            }
            if let message = message ?? cloud.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .storyFormStyle()
        .navigationTitle("Your Voices").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $enrolling) { NavigationStack { VoiceEnrollmentView() } }
        .confirmationDialog("Delete this voice?", isPresented: Binding(get: { deletingVoice != nil }, set: { if !$0 { deletingVoice = nil } }), titleVisibility: .visible) {
            Button("Delete Voice", role: .destructive) {
                guard let voice = deletingVoice else { return }
                deletingVoice = nil
                Task { do { try await cloud.deleteVoice(profileID: voice.id) } catch { message = error.localizedDescription } }
            }
        } message: { Text("Its samples and reusable voice will be removed. Narration already saved in your books remains.") }
        .confirmationDialog("Delete your voice account?", isPresented: $deleteAccount, titleVisibility: .visible) {
            Button("Delete Voice Account", role: .destructive) {
                Task { do { try await cloud.deleteAccount() } catch { message = error.localizedDescription } }
            }
        } message: { Text("Your saved voices, recordings, and cloud narration will be removed. Books already saved to your library remain.") }
        .onChange(of: cloud.jobs.map { $0.id + $0.state }) { _, _ in receivePreview() }
        .onChange(of: preview.playingURL) { _, url in if url != nil { auditionedVoiceID = previewVoiceID } }
        .onChange(of: cloud.userID) { _, _ in operation?.cancel(); enrolling = false; deletingVoice = nil; message = nil; preview.stop(); previewJobID = nil; auditionedVoiceID = nil; previewLoading = false }
        .onAppear { active = true; receivePreview() }
        .onDisappear { active = false; operation?.cancel(); previewLoading = false; preview.stop() }
    }

    private func status(_ value: String) -> String {
        switch value {
        case "ready": String(localized: "Ready")
        case "processing": String(localized: "Preparing")
        case "awaitingApproval": String(localized: "Review Your Voice")
        case "deleting": String(localized: "Deleting")
        case "failed": String(localized: "Try Again")
        default: String(localized: "Unavailable")
        }
    }

    private func audition(_ voice: VoiceProfile) {
        guard let owner = cloud.userID, active else { return }
        operation?.cancel()
        preview.stop(); previewLoading = true; message = nil
        operation = Task {
            do {
                let id = try await cloud.startVoicePreview(profileID: voice.id)
                guard owner == cloud.userID, active, !Task.isCancelled else { return }
                previewVoiceID = voice.id; previewJobID = id
                receivePreview()
            } catch is CancellationError { previewLoading = false }
            catch { previewLoading = false; message = error.localizedDescription }
        }
    }

    private func receivePreview() {
        guard active, let id = previewJobID, let job = cloud.jobs.first(where: { $0.id == id }) else { return }
        if job.state == "ready", job.expiresAt > Date().timeIntervalSince1970 {
            previewJobID = nil
            guard let owner = cloud.userID, active else { return }
            let voiceID = previewVoiceID
            operation = Task {
                defer { previewLoading = false }
                do {
                    let urls = try await cloud.download(job: job)
                    guard owner == cloud.userID, active, !Task.isCancelled, let url = urls.values.first else { return }
                    previewVoiceID = voiceID; preview.toggle(url)
                } catch is CancellationError { }
                catch { message = error.localizedDescription }
            }
        } else if job.state == "failed" || job.state == "cancelled" || job.state == "expired" || job.expiresAt <= Date().timeIntervalSince1970 {
            previewJobID = nil; previewLoading = false
            message = job.state == "expired" || job.expiresAt <= Date().timeIntervalSince1970
                ? CloudNarrationFailure.expired.localizedDescription
                : String(localized: "This preview could not be created. Try again.")
        }
    }
}
