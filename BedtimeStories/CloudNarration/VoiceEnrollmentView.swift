import SwiftUI

struct VoiceEnrollmentView: View {
    private enum Take: String, Identifiable { case reference, consent; var id: String { rawValue } }
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
                    .onChange(of: name) { _, value in if value.count > 80 { name = String(value.prefix(80)) } }
                Picker("Language", selection: $language) {
                    Text("English").tag("en-US")
                    Text("Polish").tag("pl-PL")
                }
                Toggle("I am an adult recording my own voice", isOn: $confirmsOwnVoice)
                Toggle("Keep my voice sample and consent recording until I delete my voice", isOn: $retentionAccepted)
                Text("Keeping these recordings lets us recreate your voice if needed. You can delete them together with your voice at any time.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("To prepare your voice and narrate stories, your recordings and story text are sent to Google. Processing may take place outside Europe.")
                    .font(.footnote).foregroundStyle(.secondary)
                if enrollment == nil {
                    Button("Continue") { begin() }
                        .disabled(!confirmsOwnVoice || !retentionAccepted || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                }
            } header: { Text("Your Voice") } footer: {
                Text("Use a quiet room and your normal speaking voice. You will record a voice sample and a separate consent statement.")
            }
            .disabled(enrollment != nil)
            if let enrollment {
                Section {
                    Text("Speak naturally for 10–30 seconds. Keep the microphone at a comfortable distance and avoid music or other voices.")
                    Button(referenceURL == nil ? "Record Voice Sample" : "Record Voice Sample Again", systemImage: "mic") { recording = .reference }
                    if referenceURL != nil { Label("Voice sample ready", systemImage: "checkmark.circle") }
                } header: { Text("1. Voice Sample") }
                Section {
                    Text(enrollment.consentStatement).textSelection(.enabled)
                        .accessibilityIdentifier("voice-consent-statement")
                    Button(consentURL == nil ? "Record Consent Statement" : "Record Consent Again", systemImage: "mic") { recording = .consent }
                    if consentURL != nil { Label("Consent recording ready", systemImage: "checkmark.circle") }
                } header: { Text("2. Your Consent") } footer: {
                    Text("Read this statement exactly as shown. Record it separately from your voice sample.")
                }
                Section {
                    Button("Create My Voice", systemImage: "waveform.badge.plus") { upload(enrollment) }
                        .disabled(referenceURL == nil || consentURL == nil || working || cloud.userID == nil)
                        .accessibilityIdentifier("create-private-voice")
                    Text("Your recordings will be uploaded securely to create a reusable voice. You can delete your voice and its original samples from Your Voices.").font(.footnote).foregroundStyle(.secondary)
                    Button("Start Again", role: .destructive) { restart() }.disabled(working)
                }
            }
            if working { ProgressView("Preparing your voice…") }
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .storyFormStyle().disabled(working)
        .navigationTitle("Add Your Voice").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) } }
        .sheet(item: $recording) { take in
            RecordingView(text: take == .consent ? enrollment?.consentStatement ?? "" : referenceScript) { url in
                await accept(url, take: take)
            }
        }
        .onChange(of: cloud.userID) { _, _ in dismiss() }
        .onDisappear {
            operation?.cancel()
            let urls = [referenceURL, consentURL].compactMap { $0 }
            Task { await VoiceEnrollmentAudio.shared.remove(urls) }
        }
    }

    private var referenceScript: String {
        language == "pl-PL"
            ? "Pod koniec dnia robi się spokojnie. Zamykamy książkę, gasimy światło i słuchamy cichych dźwięków za oknem. Za chwilę opowiem ci historię o małym lisie, który szukał drogi do domu."
            : "At the end of the day, everything becomes quiet. We close our book, turn down the light, and listen to the soft sounds outside. In a moment, I will tell you a story about a little fox who was finding the way home."
    }

    private func begin() {
        operation?.cancel(); working = true; message = nil
        operation = Task {
            defer { working = false }
            do { enrollment = try await cloud.beginEnrollment(name: name.trimmingCharacters(in: .whitespacesAndNewlines), language: language, retentionAccepted: retentionAccepted) }
            catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }

    private func accept(_ url: URL, take: Take) async -> Bool {
        guard let owner = cloud.userID else { return false }
        do {
            let prepared = try await VoiceEnrollmentAudio.shared.prepare(url, userID: owner, consent: take == .consent)
            guard cloud.userID == owner, !Task.isCancelled else { await VoiceEnrollmentAudio.shared.remove([prepared]); return false }
            let previous = take == .reference ? referenceURL : consentURL
            if take == .reference { referenceURL = prepared } else { consentURL = prepared }
            if let previous { await VoiceEnrollmentAudio.shared.remove([previous]) }
            return true
        } catch is CancellationError { return false }
        catch { message = error.localizedDescription; return false }
    }

    private func upload(_ enrollment: VoiceEnrollment) {
        guard let referenceURL, let consentURL else { return }
        operation?.cancel(); working = true; message = nil
        operation = Task {
            defer { working = false }
            do {
                _ = try await cloud.uploadEnrollment(enrollment: enrollment, referenceURL: referenceURL, consentURL: consentURL)
                await VoiceEnrollmentAudio.shared.remove([referenceURL, consentURL])
                dismiss()
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }

    private func restart() {
        let urls = [referenceURL, consentURL].compactMap { $0 }
        enrollment = nil; referenceURL = nil; consentURL = nil; message = nil
        Task { await VoiceEnrollmentAudio.shared.remove(urls) }
    }
}
