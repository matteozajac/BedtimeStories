import CryptoKit
import SwiftUI

struct NarrationComposerView: View {
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: BookEditorModel
    @State private var preferences = NarrationDraftPreferences()
    @State private var owner: String?
    @State private var working = false
    @State private var message: String?
    @State private var accepting: NarrationJob?
    @State private var preview = NarrationAudioPreview()
    @State private var operation: Task<Void, Never>?

    private var chapters: [DraftChapter] { editor.draft.chapters.filter { !NarrationParagraphStyleView.paragraphs($0).isEmpty } }
    private var effectiveStyles: [UUID: [NarrationStyle]] {
        Dictionary(uniqueKeysWithValues: chapters.map { chapter in
            (chapter.id, NarrationParagraphStyleView.paragraphs(chapter).indices.map { preferences.styleOverrides[chapter.id]?[$0] ?? preferences.defaultStyle })
        })
    }
    private var currentHash: String { cloud.snapshotHash(draft: editor.draft, styles: effectiveStyles, defaultStyle: preferences.defaultStyle) }
    private var jobs: [NarrationJob] { cloud.jobs.filter { $0.draftId.caseInsensitiveCompare(editor.draft.id.uuidString) == .orderedSame } }

    var body: some View {
        Form {
            CloudAccountView()
            if cloud.isConfigured, cloud.isEnabled, cloud.userID != nil {
                Section {
                    Picker("Voice", selection: $preferences.voiceID) {
                        Text("Choose Your Voice").tag("")
                        ForEach(cloud.voices.filter { $0.status == "ready" }) { voice in Text(voice.displayName).tag(voice.id) }
                    }
                    NavigationLink("Manage Your Voices") { YourVoicesView() }
                    Picker("Book Style", selection: $preferences.defaultStyle) {
                        ForEach(NarrationStyle.allCases, id: \.rawValue) { style in Text(style.title).tag(style) }
                    }
                } header: { Text("Narration") } footer: {
                    Text("Choose a feeling for the whole book, then adjust individual paragraphs below. Your story’s words stay the same.")
                }
                Section("Paragraph Styles") {
                    ForEach(chapters) { chapter in
                        NavigationLink {
                            NarrationParagraphStyleView(chapter: chapter, defaultStyle: preferences.defaultStyle,
                                overrides: Binding(get: { preferences.styleOverrides[chapter.id] ?? [:] }, set: { preferences.styleOverrides[chapter.id] = $0 }))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(chapter.title.isEmpty ? String(localized: "Untitled Chapter") : chapter.title)
                                Text("\(NarrationParagraphStyleView.paragraphs(chapter).count) paragraphs").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("Preview Opening", systemImage: "play.circle") { start(previewOnly: true) }
                        .disabled(cannotCreate)
                    Button("Create Book Narration", systemImage: "waveform") { start(previewOnly: false) }
                        .disabled(cannotCreate)
                        .accessibilityIdentifier("create-book-narration")
                } footer: {
                    Text("Creation continues when you close this screen. Listen and choose Use Narration before it changes your draft. Saving the book adds the audio to your library.")
                }
                if !jobs.isEmpty {
                    Section("Recent Narration") {
                        ForEach(jobs) { job in jobRow(job) }
                    }
                }
                if preview.playingURL != nil { Button("Stop Preview", systemImage: "stop.circle", action: preview.stop) }
                if working { ProgressView("Preparing narration…") }
            }
            if let message = message ?? cloud.message ?? preview.message { Text(message).foregroundStyle(.secondary).font(.footnote) }
        }
        .storyFormStyle()
        .navigationTitle("Create Narration").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) } }
        .task(id: cloud.userID) { loadPreferences() }
        .onChange(of: preferences) { _, _ in savePreferences() }
        .onChange(of: cloud.userID) { _, _ in operation?.cancel(); preview.stop(); accepting = nil; owner = nil; preferences = NarrationDraftPreferences(); message = nil }
        .onDisappear { operation?.cancel(); preview.stop() }
        .confirmationDialog("Use this narration?", isPresented: Binding(get: { accepting != nil }, set: { if !$0 { accepting = nil } }), titleVisibility: .visible) {
            Button("Use Narration") { if let job = accepting { accepting = nil; accept(job) } }
        } message: { Text("This replaces the narration in your working draft. Your library book changes only when you save it.") }
    }

    private var cannotCreate: Bool {
        working || cloud.isWorking || owner != cloud.userID || chapters.isEmpty ||
        !cloud.voices.contains(where: { $0.id == preferences.voiceID && $0.status == "ready" })
    }

    @ViewBuilder private func jobRow(_ job: NarrationJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.preview ? "Opening Preview" : "Book Narration").font(.headline)
            if job.state == "queued" || job.state == "processing" {
                ProgressView(value: min(1, max(0, job.progress))) { Text(job.state == "queued" ? "Waiting to create narration…" : "Creating narration…") }
                Button("Cancel Creation", role: .cancel) {
                    Task {
                        do { try await cloud.cancel(jobID: job.id) }
                        catch {
                            CloudNarrationDiagnostics.reportIfNeeded("Narration cancellation failed", error: error)
                            if !(error is CancellationError) { message = error.localizedDescription }
                        }
                    }
                }.disabled(working || cloud.isWorking)
            } else if job.state == "ready", job.expiresAt > Date().timeIntervalSince1970 {
                Button("Listen to Narration", systemImage: "play.circle") { listen(job) }.disabled(working)
                if !job.preview {
                    Button("Use Narration", systemImage: "checkmark.circle") { accepting = job }
                        .disabled(working || job.snapshotHash != currentHash)
                    if job.snapshotHash != currentHash { Text("The text or narration settings have changed. Create a new narration to match them.").font(.footnote).foregroundStyle(.secondary) }
                }
            } else {
                if job.state == "expired" || job.expiresAt <= Date().timeIntervalSince1970 {
                    Text("This narration has expired. Create it again to continue.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(job.state == "cancelled" ? "Creation cancelled. Your book is unchanged." : "Narration could not be completed. Your book is unchanged; try again.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 4)
    }

    private func loadPreferences() {
        guard let userID = cloud.userID else { return }
        owner = userID
        preferences = NarrationDraftPreferences.load(userID: userID, draftID: editor.draft.id)
        for chapter in chapters {
            // A title matching the first line is omitted during paragraph parsing, so it
            // belongs to the fingerprint alongside the text when retaining overrides.
            let contents: Data
            do { contents = try JSONEncoder().encode([chapter.title, chapter.text]) }
            catch {
                AppLog.error("Narration chapter fingerprint encoding failed", error: error, category: "cloud_narration")
                contents = Data()
            }
            let hash = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
            if preferences.chapterTextHashes[chapter.id] != hash { preferences.styleOverrides[chapter.id] = nil }
            preferences.chapterTextHashes[chapter.id] = hash
        }
    }

    private func savePreferences() {
        guard let owner, owner == cloud.userID else { return }
        do { try preferences.save(userID: owner, draftID: editor.draft.id) }
        catch {
            AppLog.error("Narration draft preferences save failed", error: error, category: "cloud_narration")
            message = String(localized: "Narration settings could not be saved on this device. Keep this screen open and try again.")
        }
    }

    private func start(previewOnly: Bool) {
        guard let owner, owner == cloud.userID else { return }
        operation?.cancel(); working = true; message = nil
        let draft = editor.draft; let styles = effectiveStyles
        operation = Task {
            defer { working = false }
            do {
                _ = try await cloud.startNarration(draft: draft, voiceID: preferences.voiceID, styles: styles, defaultStyle: preferences.defaultStyle, preview: previewOnly)
                guard owner == cloud.userID, !Task.isCancelled else { return }
            } catch is CancellationError { AppLog.trace("Narration composer submission cancelled", category: "cloud_narration") }
            catch {
                CloudNarrationDiagnostics.reportIfNeeded("Narration composer submission failed", error: error)
                message = error.localizedDescription
            }
        }
    }

    private func listen(_ job: NarrationJob) {
        guard let owner, owner == cloud.userID else { return }
        operation?.cancel(); working = true; message = nil
        operation = Task {
            defer { working = false }
            do {
                let urls = try await cloud.download(job: job)
                guard owner == cloud.userID, !Task.isCancelled else { return }
                guard let first = editor.draft.chapters.compactMap({ urls[$0.id] }).first else { throw BookError.invalid("The preview is unavailable.") }
                preview.toggle(first)
            } catch is CancellationError { AppLog.trace("Narration composer preview cancelled", category: "cloud_narration") }
            catch {
                CloudNarrationDiagnostics.reportIfNeeded("Narration composer preview failed", error: error)
                message = error.localizedDescription
            }
        }
    }

    private func accept(_ job: NarrationJob) {
        guard let owner, owner == cloud.userID, !job.preview, job.snapshotHash == currentHash else { return }
        let snapshot = editor.draft
        let hash = currentHash
        operation?.cancel(); working = true; message = nil; preview.stop()
        operation = Task {
            defer { working = false }
            do {
                let urls = try await cloud.download(job: job)
                guard owner == cloud.userID, !Task.isCancelled, hash == currentHash else { return }
                if await editor.setGeneratedAudio(urls, expectedSnapshot: snapshot, authorized: { owner == cloud.userID && !Task.isCancelled }) { dismiss() }
                else { message = editor.message }
            } catch is CancellationError { AppLog.trace("Narration attachment cancelled", category: "cloud_narration") }
            catch {
                CloudNarrationDiagnostics.reportIfNeeded("Narration attachment failed", error: error)
                message = error.localizedDescription
            }
        }
    }
}
