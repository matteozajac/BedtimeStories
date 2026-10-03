import MZAppFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChapterEditorView: View {
    @Bindable var editor: BookEditorModel
    let chapterID: UUID
    @State private var recording = false
    @State private var importAudio = false
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var removeAudio = false
    @State private var preview = DraftAudioPreview()

    private var diagnosticFields: [String: TelemetryValue] {
        var values: [String: TelemetryValue] = ["draft_id": .string(editor.draft.id.uuidString)]
        if let source = editor.draft.source { values["book_id"] = .string(source.bookID.uuidString) }
        values["chapter_id"] = .string(chapterID.uuidString)
        return values
    }

    var body: some View {
        Group {
            if let index = editor.draft.chapters.firstIndex(where: { $0.id == chapterID }) {
                let chapter = editor.draft.chapters[index]
                Form {
                    Section("Chapter Details") {
                        TextField("Chapter title (optional)", text: $editor.draft.chapters[index].title).storyFont(.title3, weight: .semibold)
                        TextEditor(text: $editor.draft.chapters[index].text)
                            .storyFont(.body).lineSpacing(6).foregroundStyle(Theme.ink)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260).accessibilityLabel("Chapter text").accessibilityIdentifier("draft-chapter-text")
                    }
                    .listRowBackground(Theme.surface)
                    Section("Picture") {
                        DraftImageView(path: chapter.image, draftID: editor.draft.id, store: editor.store)
                        PhotosPicker(selection: $photo, matching: .images) { Label(chapter.image == nil ? "Add Chapter Photo" : "Change Chapter Photo", systemImage: "photo") }
                        BookIllustrationButton(editor: editor, chapterID: chapterID)
                        if chapter.image != nil { Button("Remove Picture", role: .destructive) { editor.draft.chapters[index].image = nil; AppLog.trace("Chapter picture removed", category: "creator", metadata: diagnosticFields) } }
                    }
                    .listRowBackground(Theme.surface)
                    Section {
                        if let path = chapter.audio {
                            HStack(spacing: 14) {
                                Button(preview.playingPath == path ? "Stop Preview" : "Play Narration", systemImage: preview.playingPath == path ? "stop.fill" : "play.fill") {
                                    preview.toggle(path: path, draftID: editor.draft.id, store: editor.store)
                                }
                                .labelStyle(.iconOnly).font(.body.weight(.bold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 44, height: 44).background(Theme.accent, in: .circle)
                                .buttonStyle(.pressable).disabled(preview.loading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preview.playingPath == path ? "Stop Preview" : "Play Narration").font(.body.weight(.semibold))
                                    Label(Duration.seconds(chapter.audioDuration ?? 0).formatted(.time(pattern: .minuteSecond)), systemImage: "waveform")
                                        .font(.subheadline).foregroundStyle(.secondary).labelStyle(CompactLabelStyle())
                                }
                                .accessibilityHidden(true)
                            }
                            .padding(.vertical, 4)
                        }
                        Button(chapter.audio == nil ? "Record Narration" : "Record a New Take", systemImage: "mic.fill") {
                            preview.stop(); recording = true
                        }.disabled(editor.draft.audio != nil).accessibilityIdentifier("record-narration")
                        Button("Import Audio", systemImage: "square.and.arrow.down") { preview.stop(); importAudio = true }.disabled(editor.draft.audio != nil)
                        if editor.draft.audio != nil { Text("Remove the full-book narration in Book Details before recording individual chapters.").font(.footnote).foregroundStyle(.secondary) }
                        if chapter.audio != nil {
                            Button("Remove Narration", role: .destructive) { removeAudio = true }
                                .confirmationDialog("Remove this chapter’s narration?", isPresented: $removeAudio, titleVisibility: .visible) {
                                    Button("Remove Narration", role: .destructive) {
                                        preview.stop(); editor.draft.chapters[index].audio = nil; editor.draft.chapters[index].audioDuration = nil
                                        AppLog.trace("Chapter narration removed", category: "creator", metadata: diagnosticFields)
                                    }
                                }
                        }
                    } header: { Text("Your Voice") } footer: { Text("Record a chapter at a time. Review each take before keeping it. Imported audio can be M4A, MP3, or WAV.") }
                    .listRowBackground(Theme.surface)
                    if editor.working || loadingPhoto { ProgressView("Saving…").listRowBackground(Theme.surface) }
                }.storyFormStyle().scrollDismissesKeyboard(.interactively).disabled(editor.working || loadingPhoto)
                .sheet(isPresented: $recording) {
                    RecordingView(text: chapter.text) { url in await editor.setAudio(url, chapterID: chapterID) }
                }
            }
        }
        .navigationTitle("Edit Chapter").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editor.working || loadingPhoto)
        .fileImporter(isPresented: $importAudio, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): Task { _ = await editor.setAudio(url, chapterID: chapterID) }
            case .failure(let error):
                AppLog.error("Chapter recording selection failed", error: error, category: "creator", metadata: diagnosticFields)
                editor.message = error.localizedDescription
            }
        }
        .task(id: photo) {
            guard let photo else { return }
            loadingPhoto = true
            defer { loadingPhoto = false }
            AppLog.trace("Chapter photo transfer started", category: "creator", metadata: diagnosticFields)
            do {
                if let data = try await photo.loadTransferable(type: Data.self) {
                    AppLog.trace("Chapter photo transfer completed", category: "creator", metadata: diagnosticFields.merging(["byte_count": .integer(data.count)]) { _, new in new })
                    await editor.setImage(data, chapterID: chapterID)
                } else { AppLog.warning("Chapter photo transfer returned no image data", category: "creator", metadata: diagnosticFields) }
            }
            catch is CancellationError { AppLog.trace("Chapter photo loading cancelled", category: "creator", metadata: diagnosticFields) }
            catch {
                AppLog.error("Chapter photo loading failed", error: error, category: "creator", metadata: diagnosticFields)
                editor.message = String(localized: "The photo could not be opened. Try another photo.")
            }
        }
        .onAppear { AppLog.trace("Chapter editor opened", category: "creator", metadata: diagnosticFields) }
        .onDisappear { preview.stop(); AppLog.trace("Chapter editor closed", category: "creator", metadata: diagnosticFields) }
        .alert("Unable to play", isPresented: Binding(get: { preview.message != nil }, set: { if !$0 { preview.message = nil } })) { } message: { Text(preview.message ?? "") }
    }
}
