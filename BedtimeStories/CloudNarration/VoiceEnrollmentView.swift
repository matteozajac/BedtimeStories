import SwiftUI

struct VoiceEnrollmentView: View {
    private enum Take: String, Identifiable { case reference, consent; var id: String { rawValue } }
    @Environment(OperationCenter.self) private var operations
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var language = "en-US"
    @State private var enrollment: VoiceEnrollment?
    @State private var referenceURL: URL?
    @State private var consentURL: URL?
    @State private var recording: Take?
    @State private var confirmsOwnVoice = false
    @State private var retentionAccepted = false
    @State private var working = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Voice name", text: $name).textContentType(.nickname)
                    .storyFont(.title3, weight: .semibold).foregroundStyle(Theme.ink)
                    .onChange(of: name) { _, value in if value.count > 80 { name = String(value.prefix(80)) } }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Language")
                    Picker("Language", selection: $language) {
                        Text("English").tag("en-US")
                        Text("Polish").tag("pl-PL")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                .padding(.vertical, 4)
                Toggle("I am an adult recording my own voice", isOn: $confirmsOwnVoice).tint(Theme.accent)
                Toggle("Keep my voice sample and consent recording until I delete my voice", isOn: $retentionAccepted).tint(Theme.accent)
                Label {
                    Text("Keeping these recordings lets us recreate your voice if needed. You can delete them together with your voice at any time.")
                        .font(.footnote).foregroundStyle(.secondary)
                } icon: { Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.glow) }
                Label {
                    Text("To prepare your voice and narrate stories, your recordings and story text are sent to Google. Processing may take place outside Europe.")
                        .font(.footnote).foregroundStyle(.secondary)
                } icon: { Image(systemName: "globe").font(.footnote).foregroundStyle(Theme.glow) }
            } header: { Text("Your Voice") } footer: {
                Text("Use a quiet room and your normal speaking voice. You will record a voice sample and a separate consent statement.")
            }
            .listRowBackground(Theme.surface)
            .disabled(enrollment != nil)
            if enrollment == nil {
                Section {
                    Button { begin() } label: { Label("Continue", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle()) }
                        .buttonStyle(.storyProminent(fullWidth: true))
                        .disabled(!confirmsOwnVoice || !retentionAccepted || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let enrollment {
                Section {
                    Text("Speak naturally for 10–30 seconds. Keep the microphone at a comfortable distance and avoid music or other voices.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    takeRow(ready: referenceURL != nil, readyTitle: "Voice sample ready",
                            title: referenceURL == nil ? "Record Voice Sample" : "Record Voice Sample Again") {
                        AppLog.debug("Voice reference recording requested", category: "cloud_narration", metadata: ["replacing_take": .bool(referenceURL != nil)])
                        recording = .reference
                    }
                } header: { Text("1. Voice Sample") }
                .listRowBackground(Theme.surface)
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Capsule().fill(Theme.glow).frame(width: 3).accessibilityHidden(true)
                        Text(enrollment.consentStatement).storyFont(.body).italic().lineSpacing(4).foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("voice-consent-statement")
                    }
                    .padding(.vertical, 6)
                    takeRow(ready: consentURL != nil, readyTitle: "Consent recording ready",
                            title: consentURL == nil ? "Record Consent Statement" : "Record Consent Again") {
                        AppLog.debug("Voice consent recording requested", category: "cloud_narration", metadata: ["replacing_take": .bool(consentURL != nil)])
                        recording = .consent
                    }
                } header: { Text("2. Your Consent") } footer: {
                    Text("Read this statement exactly as shown. Record it separately from your voice sample.")
                }
                .listRowBackground(Theme.surface)
                Section {
                    VStack(spacing: 12) {
                        Button("Create My Voice", systemImage: "waveform.badge.plus") { upload(enrollment) }
                            .buttonStyle(.storyProminent(fullWidth: true))
                            .disabled(referenceURL == nil || consentURL == nil || working || cloud.userID == nil)
                            .accessibilityIdentifier("create-private-voice")
                        Text("Your recordings will be uploaded securely to create a reusable voice. You can delete your voice and its original samples from Your Voices.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Start Again", role: .destructive) { restart() }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .disabled(working)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if working {
                Section {
                    HStack(spacing: 14) {
                        ProgressView().tint(Theme.glow)
                        Text("Preparing your voice…").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            if let message {
                Section { NoteCard(systemImage: "info.circle.fill", text: Text(message)) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .storyFormStyle().disabled(working)
        .navigationTitle("Add Your Voice").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
            AppLog.debug("Voice enrollment dismissed by user", category: "cloud_narration")
            dismiss()
        }.disabled(working) } }
        .sheet(item: $recording) { take in
            RecordingView(text: take == .consent ? enrollment?.consentStatement ?? "" : referenceScript) { url in
                await accept(url, take: take)
            }
        }
        .onAppear { AppLog.debug("Voice enrollment screen opened", category: "cloud_narration") }
        .onChange(of: cloud.userID) { _, _ in
            AppLog.trace("Voice enrollment dismissed after account state changed", category: "cloud_narration")
            dismiss()
        }
        .onDisappear {
            AppLog.trace("Voice enrollment screen closed", category: "cloud_narration", metadata: ["working": .bool(working), "has_reference": .bool(referenceURL != nil), "has_consent": .bool(consentURL != nil)])
            operation?.cancel()
            let urls = [referenceURL, consentURL].compactMap { $0 }
            Task { await VoiceEnrollmentAudio.shared.remove(urls) }
        }
    }

    /// A recording step: a capsule button to record, and a check once a take is kept.
    private func takeRow(ready: Bool, readyTitle: LocalizedStringKey, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if ready {
                Label(readyTitle, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ready)
            }
            if ready {
                Button(title, systemImage: "mic.fill", action: action).buttonStyle(.storySoft(fullWidth: true)).controlSize(.small)
            } else {
                Button(title, systemImage: "mic.fill", action: action).buttonStyle(.storyRecord).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var referenceScript: String {
        language == "pl-PL"
            ? "Pod koniec dnia robi się spokojnie. Zamykamy książkę, gasimy światło i słuchamy cichych dźwięków za oknem. Za chwilę opowiem ci historię o małym lisie, który szukał drogi do domu."
            : "At the end of the day, everything becomes quiet. We close our book, turn down the light, and listen to the soft sounds outside. In a moment, I will tell you a story about a little fox who was finding the way home."
    }

    private func begin() {
        AppLog.debug("Voice enrollment continue requested", category: "cloud_narration", metadata: ["language": .string(["en-US", "pl-PL"].contains(language) ? language : "unknown"), "retention_accepted": .bool(retentionAccepted)])
        operation?.cancel(); working = true; message = nil
        operation = Task {
            defer { working = false }
            do {
                enrollment = try await cloud.beginEnrollment(name: name.trimmingCharacters(in: .whitespacesAndNewlines), language: language, retentionAccepted: retentionAccepted)
                AppLog.debug("Voice enrollment screen ready for recordings", category: "cloud_narration")
            }
            catch is CancellationError { AppLog.trace("Voice enrollment screen operation cancelled", category: "cloud_narration", metadata: ["operation": .string("begin_enrollment")]) }
            catch {
                CloudNarrationDiagnostics.reportIfNeeded("Voice enrollment could not start", error: error)
                message = error.localizedDescription
            }
        }
    }

    private func accept(_ url: URL, take: Take) async -> Bool {
        guard let owner = cloud.userID else {
            AppLog.warning("Voice recording acceptance rejected because no account is signed in", category: "cloud_narration", metadata: ["recording_kind": .string(take.rawValue)])
            return false
        }
        AppLog.trace("Voice recording acceptance started", category: "cloud_narration", metadata: ["recording_kind": .string(take.rawValue)])
        do {
            let prepared = try await VoiceEnrollmentAudio.shared.prepare(url, userID: owner, consent: take == .consent)
            guard cloud.userID == owner, !Task.isCancelled else {
                AppLog.trace("Prepared voice recording discarded after account change or cancellation", category: "cloud_narration", metadata: ["recording_kind": .string(take.rawValue), "cancelled": .bool(Task.isCancelled)])
                await VoiceEnrollmentAudio.shared.remove([prepared]); return false
            }
            let previous = take == .reference ? referenceURL : consentURL
            if take == .reference { referenceURL = prepared } else { consentURL = prepared }
            if let previous { await VoiceEnrollmentAudio.shared.remove([previous]) }
            AppLog.debug("Voice recording accepted for enrollment", category: "cloud_narration", metadata: ["recording_kind": .string(take.rawValue), "replaced_previous_take": .bool(previous != nil)])
            return true
        } catch is CancellationError {
            AppLog.trace("Voice recording acceptance cancelled", category: "cloud_narration")
            return false
        }
        // VoiceEnrollmentAudio owns diagnostics before it translates an audio SDK error.
        catch {
            AppLog.trace("Voice enrollment recording remains unavailable after preparation failure", category: "cloud_narration", metadata: ["recording_kind": .string(take.rawValue)])
            message = error.localizedDescription; return false
        }
    }

    private func upload(_ enrollment: VoiceEnrollment) {
        guard let referenceURL, let consentURL, let owner = cloud.userID else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString
        let pending = PendingVoiceUpload(operationID: id, ownerID: owner, enrollment: enrollment)
        do { try pending.stage(reference: referenceURL, consent: consentURL) }
        catch { pending.remove(); message = String(localized: "Your recordings could not be saved for upload. Free some space and try again."); return }
        operations.start(kind: .voiceEnrollment, title: title, subtitle: String(localized: "Uploading your recordings…"), destination: .voices, ownerID: owner, id: id) { _ in
            try await pending.submit(cloud: cloud, center: operations)
        }
        Task { await VoiceEnrollmentAudio.shared.remove([referenceURL, consentURL]) }
        // The operation owns the recordings until submission completes.
        self.referenceURL = nil; self.consentURL = nil
        Task { await operations.requestNotificationAuthorization() }
        dismiss()
    }

    private func restart() {
        AppLog.debug("Voice enrollment restarted by user", category: "cloud_narration", metadata: ["has_reference": .bool(referenceURL != nil), "has_consent": .bool(consentURL != nil)])
        let urls = [referenceURL, consentURL].compactMap { $0 }
        enrollment = nil; referenceURL = nil; consentURL = nil; message = nil
        Task { await VoiceEnrollmentAudio.shared.remove(urls) }
    }
}
