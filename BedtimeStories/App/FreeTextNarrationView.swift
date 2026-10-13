import MZAppFoundation
import SwiftUI

struct FreeTextNarrationView: View {
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(OperationCenter.self) private var operations
    @Environment(DeveloperOptions.self) private var options
    @State private var text = ""
    @State private var language = StoryLanguage.preferred
    @State private var voiceID = ""
    @State private var style = NarrationStyle.natural
    @State private var preview = NarrationAudioPreview()
    @State private var listeningJobID: String?
    @State private var listeningRequestID = UUID()
    @State private var downloading = false
    @State private var message: String?

    private var voices: [VoiceProfile] { VoiceProfile.available(for: language, personalVoices: cloud.voices) }
    private var jobs: [NarrationJob] {
        cloud.jobs.filter { $0.draftId.caseInsensitiveCompare(FreeTextNarrationDraft.id.uuidString) == .orderedSame }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var activeOperations: [AppOperation] {
        operations.visibleOperations.filter { $0.destination == .narration(FreeTextNarrationDraft.id) && $0.isActive }
    }
    private var canGenerate: Bool {
        options.isEnabled && cloud.isConfigured && cloud.isEnabled && cloud.userID != nil &&
        FreeTextNarrationDraft.isValid(text) && voices.contains { $0.id == voiceID } &&
        activeOperations.isEmpty && !jobs.contains { $0.state == "queued" || $0.state == "processing" }
    }

    var body: some View {
        Form {
            if options.isEnabled {
                if cloud.isConfigured && cloud.isEnabled {
                    CloudAccountView()
                } else {
                    Section {
                        Text("Free text narration requires a cloud-enabled build and a signed-in voice account.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Narration") {
                    Picker("Narration Language", selection: $language) {
                        ForEach(StoryLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("developer.narration-language")
                    Picker("Voice", selection: $voiceID) {
                        Section("Your Voices") {
                            ForEach(voices.filter { !$0.isBuiltIn }) { Text($0.displayName).tag($0.id) }
                        }
                        Section("Storytellers") {
                            ForEach(voices.filter(\.isBuiltIn)) { Text($0.displayName).tag($0.id) }
                        }
                    }
                    .accessibilityIdentifier("developer.narration-voice")
                    Picker("Delivery Style", selection: $style) {
                        ForEach(NarrationStyle.allCases) { Text($0.title).tag($0) }
                    }
                    NavigationLink("Manage Your Voices") { YourVoicesView() }
                }
                Section {
                    TextField("Text to Read", text: $text, axis: .vertical)
                        .lineLimit(6...14)
                        .accessibilityIdentifier("developer.narration-text")
                    Text("\(text.utf16.count) / 4,000 characters")
                        .font(.caption).foregroundStyle(text.utf16.count > FreeTextNarrationDraft.maximumCharacters ? Color.red : Color.secondary)
                    Button("Generate Audio", systemImage: "waveform", action: generate)
                        .disabled(!canGenerate)
                        .opacity(canGenerate ? 1 : 0.45)
                        .accessibilityIdentifier("developer.generate-audio")
                } header: {
                    Text("Free Text")
                } footer: {
                    Text("The complete text is processed by the cloud voice service. Audio stays separate from your book library. Generation continues after you close this screen; return here to listen.")
                }
                if !activeOperations.isEmpty {
                    Section("Background Activity") {
                        ForEach(activeOperations) { operation in operationRow(operation) }
                    }
                }
                if !jobs.isEmpty {
                    Section("Generated Audio") {
                        ForEach(jobs.prefix(10)) { job in audioRow(job) }
                    }
                }
                if downloading || preview.loading {
                    Section { ProgressView("Downloading narration…") }
                }
                if preview.playingURL != nil {
                    Section {
                        Button("Stop Preview", systemImage: "stop.fill", action: preview.stop)
                    }
                }
                if let error = message ?? preview.message ?? cloud.message {
                    Section { Text(error).foregroundStyle(.secondary) }
                }
            } else {
                Section { Text("Enable Developer Mode to generate free text narration.") }
            }
        }
        .storyFormStyle()
        .navigationTitle("Free Text Narration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectAvailableVoice() }
        .onChange(of: language) { selectAvailableVoice() }
        .onChange(of: cloud.voices) { selectAvailableVoice() }
        .onChange(of: cloud.userID) {
            stopListening()
            text = ""; message = nil; voiceID = ""
            selectAvailableVoice()
        }
        .onChange(of: options.isEnabled) { if !options.isEnabled { stopListening() } }
        .task(id: listeningRequestID) {
            guard let id = listeningJobID, let job = jobs.first(where: { $0.id == id }) else { return }
            await listen(job)
        }
        .onDisappear { stopListening() }
    }

    @ViewBuilder private func audioRow(_ job: NarrationJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date(timeIntervalSince1970: job.createdAt), format: .dateTime.month().day().hour().minute())
                .font(.subheadline)
            if let voice = (cloud.voices + VoiceProfile.builtInVoices).first(where: { $0.id == job.voiceProfileId }) {
                Text(voice.displayName).font(.caption).foregroundStyle(.secondary)
            }
            if job.state == "ready" {
                if job.expiresAt > Date().timeIntervalSince1970 {
                    Button("Listen to Narration", systemImage: "play.fill") {
                        preview.stop(); message = nil
                        listeningJobID = job.id
                        listeningRequestID = UUID()
                    }
                    .disabled(downloading || preview.loading)
                } else {
                    Text("This audio has expired. Generate it again.").foregroundStyle(.secondary)
                }
            } else if job.state == "queued" || job.state == "processing" {
                Text("Creating narration").foregroundStyle(.secondary)
            } else if job.state == "cancelled" {
                Text("Creation cancelled.").foregroundStyle(.secondary)
            } else {
                Text("Audio generation failed. Try again.").foregroundStyle(.secondary)
            }
        }
    }

    private func operationRow(_ operation: AppOperation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(operation.subtitle)
            if let progress = operation.progress { ProgressView(value: progress) }
            else { ProgressView() }
            Button("Cancel", role: .cancel) { operations.cancel(id: operation.id) }
                .disabled(!operation.canCancel)
        }
    }

    private func selectAvailableVoice() {
        if !voices.contains(where: { $0.id == voiceID }) { voiceID = voices.first?.id ?? "" }
    }

    private func generate() {
        guard canGenerate, let owner = cloud.userID else { return }
        stopListening(); message = nil
        do {
            let title = String(localized: "Free Text Narration")
            let draft = try FreeTextNarrationDraft.make(text: text, title: title)
            let selectedVoice = voiceID; let selectedStyle = style
            operations.start(kind: .narration, title: title, subtitle: String(localized: "Creating narration"),
                destination: .narration(FreeTextNarrationDraft.id), ownerID: owner) { id in
                let jobID = try await cloud.startNarration(draft: draft, voiceID: selectedVoice, styles: [:],
                    defaultStyle: selectedStyle, preview: false, operationID: id, plainText: true)
                operations.attachRemote(id, remoteID: jobID)
                cloud.refreshOperations()
            }
        } catch { message = error.localizedDescription }
    }

    private func listen(_ job: NarrationJob) async {
        guard options.isEnabled, let owner = cloud.userID else { return }
        downloading = true
        defer { downloading = false }
        do {
            let urls = try await cloud.download(job: job)
            try Task.checkCancellation()
            guard options.isEnabled, owner == cloud.userID,
                  let chapterID = job.outputs.first.flatMap({ UUID(uuidString: $0.chapterId) }),
                  let url = urls[chapterID] else { throw CloudNarrationFailure.invalidAudio }
            preview.toggle(url)
        } catch is CancellationError {
        } catch {
            CloudNarrationDiagnostics.reportIfNeeded("Free text narration playback failed", error: error)
            if !Task.isCancelled && owner == cloud.userID { message = error.localizedDescription }
        }
    }

    private func stopListening() {
        listeningJobID = nil
        listeningRequestID = UUID()
        preview.stop(); preview.message = nil
    }
}
