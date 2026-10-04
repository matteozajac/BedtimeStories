import CryptoKit
import SwiftUI

struct NarrationComposerView: View {
    @Environment(OperationCenter.self) private var operations
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: BookEditorModel
    @State private var preferences = NarrationDraftPreferences()
    @State private var owner: String?
    @State private var active = true
    @State private var working = false
    @State private var message: String?
    @State private var accepting: NarrationJob?
    @State private var preview = NarrationAudioPreview()
    @State private var operation: Task<Void, Never>?
    @State private var waitingForDefaultVoice = false

    private var chapters: [DraftChapter] { editor.draft.chapters.filter { !NarrationParagraphStyleView.paragraphs($0).isEmpty } }
    private var effectiveStyles: [UUID: [NarrationStyle]] {
        Dictionary(uniqueKeysWithValues: chapters.map { chapter in
            (chapter.id, NarrationParagraphStyleView.paragraphs(chapter).indices.map { preferences.styleOverrides[chapter.id]?[$0] ?? preferences.defaultStyle })
        })
    }
    private var currentHash: String { cloud.snapshotHash(draft: editor.draft, styles: effectiveStyles, defaultStyle: preferences.defaultStyle) }
    private var jobs: [NarrationJob] { cloud.jobs.filter { $0.draftId.caseInsensitiveCompare(editor.draft.id.uuidString) == .orderedSame } }
    private var availableVoices: [VoiceProfile] { VoiceProfile.available(for: preferences.language, personalVoices: cloud.voices) }
    private var languageSelection: Binding<StoryLanguage> {
        Binding(get: { preferences.language }, set: { language in
            preferences.language = language
            waitingForDefaultVoice = !cloud.hasLoadedVoices
            preferences.selectAvailableVoice(personalVoices: cloud.voices)
        })
    }
    private var voiceSelection: Binding<String> {
        Binding(get: { preferences.voiceID }, set: { voiceID in
            waitingForDefaultVoice = false
            preferences.voiceID = voiceID
        })
    }

    var body: some View {
        Form {
            CloudAccountView()
            if cloud.isConfigured, cloud.isEnabled, cloud.userID != nil {
                Section {
                    Picker("Narration Language", selection: languageSelection) {
                        ForEach(StoryLanguage.allCases) { language in Text(language.title).tag(language) }
                    }
                    Picker(selection: voiceSelection) {
                        Section("Your Voices") {
                            ForEach(availableVoices.filter { !$0.isBuiltIn }) { voice in Text(voice.displayName).tag(voice.id) }
                        }
                        Section("Storytellers") {
                            ForEach(availableVoices.filter(\.isBuiltIn)) { voice in Text(voice.displayName).tag(voice.id) }
                        }
                    } label: {
                        Label { Text("Voice").foregroundStyle(Theme.ink) } icon: { IconTile(systemName: "person.wave.2.fill", size: 30) }
                    }
                    if let selected = availableVoices.first(where: { $0.id == preferences.voiceID }),
                       let description = selected.narrationDescription {
                        Label(description, systemImage: "sparkles")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    NavigationLink { YourVoicesView() } label: {
                        Label { Text("Manage Your Voices").foregroundStyle(Theme.ink) } icon: { IconTile(systemName: "slider.horizontal.3", size: 30) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Book Style").foregroundStyle(Theme.ink)
                        FlowLayout(spacing: 8) {
                            ForEach(NarrationStyle.allCases) { style in
                                Button { preferences.defaultStyle = style } label: {
                                    NarrationStyleChip(title: style.title, style: style, selected: preferences.defaultStyle == style)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityAddTraits(preferences.defaultStyle == style ? .isSelected : [])
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: { Text("Narration") } footer: {
                    Text("Choose a feeling for the whole book, then adjust individual paragraphs below. Your story’s words stay the same.")
                }
                .listRowBackground(Theme.surface)
                Section("Paragraph Styles") {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        NavigationLink {
                            NarrationParagraphStyleView(chapter: chapter, defaultStyle: preferences.defaultStyle,
                                overrides: Binding(get: { preferences.styleOverrides[chapter.id] ?? [:] }, set: { preferences.styleOverrides[chapter.id] = $0 }))
                        } label: {
                            HStack(spacing: 14) {
                                ChapterNumber(number: (editor.draft.chapters.firstIndex { $0.id == chapter.id } ?? index) + 1)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title.isEmpty ? String(localized: "Untitled Chapter") : chapter.title)
                                        .storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
                                    Text("\(NarrationParagraphStyleView.paragraphs(chapter).count) paragraphs").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
                Section {
                    VStack(spacing: 12) {
                        Button("Create Book Narration", systemImage: "waveform") { start(previewOnly: false) }
                            .buttonStyle(.storyProminent(fullWidth: true))
                            .disabled(cannotCreate)
                            .accessibilityIdentifier("create-book-narration")
                        Button("Preview Opening", systemImage: "play.fill") { start(previewOnly: true) }
                            .buttonStyle(.storySoft(fullWidth: true))
                            .disabled(cannotCreate)
                    }
                } footer: {
                    Text("Creation continues when you close this screen. Listen and choose Use Narration before it changes your draft. Saving the book adds the audio to your library.")
                        .padding(.top, 8)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if !jobs.isEmpty {
                    Section("Recent Narration") {
                        ForEach(jobs) { job in jobRow(job) }
                    }
                    .listRowBackground(Theme.surface)
                }
                if preview.playingURL != nil || working {
                    Section {
                        if preview.playingURL != nil {
                            HStack(spacing: 14) {
                                Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                                    .symbolEffect(.variableColor.iterative).accessibilityHidden(true)
                                Button("Stop Preview", systemImage: "stop.fill", action: preview.stop)
                                    .buttonStyle(.storySoft).controlSize(.small)
                            }
                        }
                        if working {
                            HStack(spacing: 14) {
                                ProgressView().tint(Theme.glow)
                                Text("Preparing narration…").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            if let message = message ?? cloud.message ?? preview.message {
                Section { NoteCard(systemImage: "info.circle.fill", text: Text(message)) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .storyFormStyle()
        .navigationTitle("Create Narration").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: cloud.userID) { loadPreferences() }
        .onChange(of: cloud.voices) { _, _ in reconcileVoiceSelection() }
        .onChange(of: cloud.hasLoadedVoices) { _, _ in reconcileVoiceSelection() }
        .onChange(of: preferences) { _, _ in savePreferences() }
        .onChange(of: cloud.userID) { _, _ in operation?.cancel(); preview.stop(); accepting = nil; owner = nil; preferences = NarrationDraftPreferences(); message = nil }
        .onAppear { active = true; AppLog.debug("Narration composer opened", category: "cloud_narration", metadata: ["narratable_chapter_count": .integer(chapters.count)]) }
        .onDisappear { active = false;
            AppLog.trace("Narration composer closed", category: "cloud_narration", metadata: ["working": .bool(working)])
            operation?.cancel(); preview.stop()
        }
        .confirmationDialog("Use this narration?", isPresented: Binding(get: { accepting != nil }, set: { if !$0 { accepting = nil } }), titleVisibility: .visible) {
            Button("Use Narration") { if let job = accepting { accepting = nil; accept(job) } }
        } message: { Text("This replaces the narration in your working draft. Your library book changes only when you save it.") }
    }

    private var cannotCreate: Bool {
        working || cloud.isWorking || owner != cloud.userID || chapters.isEmpty ||
        !availableVoices.contains(where: { $0.id == preferences.voiceID })
    }

    @ViewBuilder private func jobRow(_ job: NarrationJob) -> some View {
        let expired = job.state == "expired" || job.expiresAt <= Date().timeIntervalSince1970
        let active = job.state == "queued" || job.state == "processing"
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                IconTile(systemName: job.preview ? "play.circle.fill" : "waveform",
                         color: active ? Theme.glow : job.state == "ready" && !expired ? Theme.accent : .secondary, size: 40)
                Text(job.preview ? "Opening Preview" : "Book Narration").storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
            }
            if active {
                ProgressView(value: min(1, max(0, job.progress))) {
                    Text(job.state == "queued" ? "Waiting to create narration…" : "Creating narration…").font(.subheadline).foregroundStyle(.secondary)
                }
                .tint(Theme.glow)
                Button("Cancel Creation", role: .cancel) {
                    Task {
                        do { try await cloud.cancel(jobID: job.id) }
                        catch {
                            CloudNarrationDiagnostics.reportIfNeeded("Narration cancellation failed", error: error)
                            if !(error is CancellationError) { message = error.localizedDescription }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                .disabled(working || cloud.isWorking)
            } else if job.state == "ready", !expired {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Listen to Narration", systemImage: "play.fill") { listen(job) }
                        .buttonStyle(.storySoft(fullWidth: !job.preview))
                        .disabled(working)
                    if !job.preview {
                        Button("Use Narration", systemImage: "checkmark") { accepting = job }
                            .buttonStyle(.storyProminent(fullWidth: true))
                            .disabled(working || job.snapshotHash != currentHash)
                    }
                }
                .controlSize(.small)
                if !job.preview && job.snapshotHash != currentHash {
                    Text("The text or narration settings have changed. Create a new narration to match them.").font(.footnote).foregroundStyle(.secondary)
                }
            } else if expired {
                Text("This narration has expired. Create it again to continue.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(job.state == "cancelled" ? "Creation cancelled. Your book is unchanged." : "Narration could not be completed. Your book is unchanged; try again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func loadPreferences() {
        guard let userID = cloud.userID else { return }
        owner = userID
        preferences = NarrationDraftPreferences.load(userID: userID, draftID: editor.draft.id)
        waitingForDefaultVoice = preferences.voiceID.isEmpty && !cloud.hasLoadedVoices
        if let previous = (cloud.voices + VoiceProfile.builtInVoices).first(where: { $0.id == preferences.voiceID }) {
            preferences.language = previous.language == "pl-PL" ? .polish : .english
        } else if preferences.voiceID.isEmpty {
            preferences.language = VoiceProfile.preferredLanguage(for: chapters.map(\.text).joined(separator: "\n"))
        }
        preferences.selectAvailableVoice(personalVoices: cloud.voices, personalVoicesLoaded: cloud.hasLoadedVoices)
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

    private func reconcileVoiceSelection() {
        if waitingForDefaultVoice, cloud.hasLoadedVoices {
            waitingForDefaultVoice = false
            preferences.voiceID = ""
        }
        if let selected = cloud.voices.first(where: { $0.id == preferences.voiceID }) {
            preferences.language = selected.language == "pl-PL" ? .polish : .english
        }
        preferences.selectAvailableVoice(personalVoices: cloud.voices, personalVoicesLoaded: cloud.hasLoadedVoices)
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
        let draft = editor.draft; let styles = effectiveStyles
        let voiceID = preferences.voiceID; let style = preferences.defaultStyle
        operations.start(kind: previewOnly ? .voicePreview : .narration,
            title: draft.title.isEmpty ? String(localized: "Untitled Book") : draft.title,
            subtitle: String(localized: "Creating narration"), destination: previewOnly ? .draft(draft.id) : .narration(draft.id), ownerID: owner) { id in
            try await editor.persist()
            let jobID = try await cloud.startNarration(draft: draft, voiceID: voiceID, styles: styles, defaultStyle: style, preview: previewOnly, operationID: id)
            operations.attachRemote(id, remoteID: jobID)
            cloud.refreshOperations()
        }
        Task { await operations.requestNotificationAuthorization() }
    }

    private func listen(_ job: NarrationJob) {
        guard let owner, owner == cloud.userID else {
            AppLog.warning("Narration listening requires the current signed-in account", category: "cloud_narration")
            return
        }
        AppLog.debug("Generated narration listening requested", category: "cloud_narration", metadata: ["preview": .bool(job.preview), "output_count": .integer(job.outputs.count)])
        working = true; message = nil
        let draftID = editor.draft.id
        let chapters = editor.draft.chapters.map(\.id)
        operations.start(kind: .download, title: editor.draft.title, subtitle: String(localized: "Downloading narration…"), destination: .narration(draftID), ownerID: owner) { _ in
            defer { working = false }
            do {
                let urls = try await cloud.download(job: job)
                guard owner == cloud.userID, !Task.isCancelled else { throw CancellationError() }
                guard let first = chapters.compactMap({ urls[$0] }).first else { throw BookError.invalid("The preview is unavailable.") }
                if active { preview.toggle(first) }
            } catch {
                CloudNarrationDiagnostics.reportIfNeeded("Narration composer preview failed", error: error)
                if active, !(error is CancellationError) { message = error.localizedDescription }
                throw error
            }
        }
    }

    private func accept(_ job: NarrationJob) {
        let snapshotMatches = job.snapshotHash == currentHash
        guard let owner, owner == cloud.userID, !job.preview, snapshotMatches else {
            AppLog.warning("Generated narration attachment rejected because its draft or account changed", category: "cloud_narration", metadata: ["same_account": .bool(owner != nil && owner == cloud.userID), "preview": .bool(job.preview), "snapshot_matches": .bool(snapshotMatches)])
            return
        }
        AppLog.debug("Generated narration attachment requested", category: "cloud_narration", metadata: ["output_count": .integer(job.outputs.count)])
        let snapshot = editor.draft
        let hash = currentHash
        operation?.cancel(); working = true; message = nil; preview.stop()
        operations.start(kind: .download, title: snapshot.title.isEmpty ? String(localized: "Book Narration") : snapshot.title,
            subtitle: String(localized: "Downloading narration…"), destination: .draft(snapshot.id), ownerID: owner) { id in
            defer { working = false }
            let urls = try await cloud.download(job: job)
            guard owner == cloud.userID, !Task.isCancelled, hash == currentHash else { throw CloudNarrationFailure.staleVoice }
            guard await editor.setGeneratedAudio(urls, expectedSnapshot: snapshot, authorized: { owner == cloud.userID && !Task.isCancelled }) else {
                throw BookError.invalid(editor.message ?? String(localized: "Your draft changed. Open it to review the narration again."))
            }
            operations.update(id, progress: 1, subtitle: String(localized: "Narration added to your draft"))
        }
        dismiss()

    }
}
