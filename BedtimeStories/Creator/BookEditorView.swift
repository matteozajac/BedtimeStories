import MZAppFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BookEditorView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var editor: BookEditorModel
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var discardChanges = false
    @State private var removingChapter: UUID?
    @State private var recordingFullBook = false
    @State private var importingFullAudio = false
    @State private var removingFullAudio = false
    @State private var preview = DraftAudioPreview()
    @State private var creatingNarration = false

    init(draft: BookDraft, store: BookDraftStore) {
        _editor = State(initialValue: BookEditorModel(draft: draft, store: store))
    }

    private var diagnosticFields: [String: TelemetryValue] {
        var values: [String: TelemetryValue] = ["draft_id": .string(editor.draft.id.uuidString)]
        if let source = editor.draft.source { values["book_id"] = .string(source.bookID.uuidString) }
        return values
    }

    var body: some View {
        @Bindable var editor = editor
        let hasCover = editor.draft.cover != nil
        Form {
            Section("Book Details") {
                HStack(alignment: .top, spacing: 16) {
                    DraftCoverView(draft: editor.draft, store: editor.store).frame(width: 92, height: 138)
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Book title", text: $editor.draft.title).storyFont(.title3, weight: .bold).foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("draft-title")
                        Divider()
                        TextField("Author (optional)", text: $editor.draft.author).textContentType(.name)
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, 6)
                TextField("About this story (optional)", text: $editor.draft.summary, axis: .vertical).lineLimit(3...6).storyFont(.body)
            }
            .listRowBackground(Theme.surface)
            Section("Cover") {
                if hasCover { DraftImageView(path: editor.draft.cover, draftID: editor.draft.id, store: editor.store) }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(hasCover ? "Change Cover Photo" : "Add Cover Photo", systemImage: "photo")
                }.disabled(loadingPhoto || editor.working)
                BookIllustrationButton(editor: editor)
                if editor.draft.cover != nil { Button("Remove Cover", role: .destructive) { editor.draft.cover = nil; AppLog.trace("Book cover removed", category: "creator", metadata: diagnosticFields) } }
            }
            .listRowBackground(Theme.surface)
            Section("Reading Time") {
                LabeledContent("Words", value: editor.draft.wordCount.formatted())
                Stepper("Reading pace: \(editor.readingPace) words/minute", value: $editor.readingPace, in: 80...180, step: 10)
                Label {
                    Text("About \(StoryReadingLength.minutes(words: editor.draft.wordCount, wordsPerMinute: editor.readingPace).formatted(.number.precision(.fractionLength(1)))) minutes for the whole book.")
                } icon: { Image(systemName: "clock").foregroundStyle(Theme.glow) }
                    .accessibilityIdentifier("book-estimated-reading-time")
            }
            .listRowBackground(Theme.surface)
            if cloud.isConfigured, cloud.isEnabled {
                Section {
                    Button("Create Narration with Your Voice", systemImage: "waveform") { preview.stop(); creatingNarration = true }
                        .disabled(editor.draft.wordCount == 0)
                } header: { Text("Your Voice") }
                .listRowBackground(Theme.surface)
            }
            if let audio = editor.draft.audio {
                Section {
                    Button(preview.playingPath == audio ? "Stop Preview" : "Play Narration", systemImage: preview.playingPath == audio ? "stop.fill" : "play.fill") {
                        preview.toggle(path: audio, draftID: editor.draft.id, store: editor.store)
                    }
                    Button("Record a New Take", systemImage: "mic.fill") { preview.stop(); recordingFullBook = true }
                    Button("Import Audio", systemImage: "square.and.arrow.down") { preview.stop(); importingFullAudio = true }
                    Button("Remove Narration", role: .destructive) { removingFullAudio = true }
                        .confirmationDialog("Remove the full-book narration?", isPresented: $removingFullAudio, titleVisibility: .visible) {
                            Button("Remove Narration", role: .destructive) { preview.stop(); editor.removeFullNarration() }
                        }
                } header: { Text("Full-book Narration") } footer: {
                    Text("Remove the full-book recording to record individual chapters. Replacing it or changing chapter order clears its chapter timestamps.")
                }
                .listRowBackground(Theme.surface)
            }
            Section {
                ForEach(editor.draft.chapters.enumerated(), id: \.element.id) { number, chapter in
                    HStack {
                      NavigationLink(value: chapter.id) {
                        HStack(spacing: 14) {
                            ChapterNumber(number: number + 1)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title.isEmpty ? String(localized: "Chapter \(number + 1)") : chapter.title)
                                    .storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
                                HStack(spacing: 10) {
                                    if !chapter.text.isEmpty { Label("Text", systemImage: "text.alignleft") }
                                    if chapter.image != nil { Label("Picture", systemImage: "photo") }
                                    if chapter.audio != nil { Label("Narration", systemImage: "waveform") }
                                    if chapter.text.isEmpty && chapter.image == nil && chapter.audio == nil { Text("Ready for your story") }
                                }.font(.caption).foregroundStyle(.secondary).labelStyle(CompactLabelStyle())
                            }
                        }.padding(.vertical, 6)
                      }.accessibilityIdentifier("draft-chapter-\(number + 1)")
                      Menu {
                          Button("Move Earlier", systemImage: "arrow.up") { editor.moveChapters(from: [number], to: number - 1) }.disabled(number == 0)
                          Button("Move Later", systemImage: "arrow.down") { editor.moveChapters(from: [number], to: number + 2) }.disabled(number == editor.draft.chapters.count - 1)
                          Button("Remove Chapter", role: .destructive) { removingChapter = chapter.id }
                      } label: { Label("Chapter Options", systemImage: "ellipsis").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
                    }
                }
                .onDelete(perform: editor.deleteChapters)
                .onMove(perform: editor.moveChapters)
                Button("Add Chapter", systemImage: "plus.circle.fill", action: editor.addChapter).font(.body.weight(.semibold)).accessibilityIdentifier("add-draft-chapter")
            } header: { Text("Chapters") } footer: { Text("Open a chapter to write, add a picture, or record narration. Chapter Options lets you reorder or remove chapters.") }
            .listRowBackground(Theme.surface)
            Section {
                Label {
                    Text(editor.isEditingBook ? "Save updates this book in your library. Discard leaves the library version unchanged." : "Save adds this book to your library to read, listen, and share with your family.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } icon: { Image(systemName: "books.vertical.fill").foregroundStyle(Theme.glow) }
            }
            .listRowBackground(Theme.surface)
            if editor.working || loadingPhoto { ProgressView("Saving…").listRowBackground(Theme.surface) }
        }
        .storyFormStyle()
        .scrollDismissesKeyboard(.interactively)
        .disabled(editor.working || loadingPhoto)
        .navigationTitle(editor.isEditingBook ? "Edit Book" : "Create Book").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .navigationDestination(for: UUID.self) { ChapterEditorView(editor: editor, chapterID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editor.hasChanges ? "Discard" : "Close", role: editor.hasChanges ? .destructive : nil) {
                    if editor.hasChanges { discardChanges = true }
                    else { Task { if await editor.discardAndClose() { dismiss() } } }
                }.disabled(editor.working || loadingPhoto).accessibilityIdentifier("close-book-editor")
                    .confirmationDialog("Discard your changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { Task { if await editor.discardAndClose() { dismiss() } } }
                        Button("Cancel", role: .cancel) { }
                    } message: { Text("Changes from this editing session will be discarded. Your library book stays unchanged.") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(editor.working || loadingPhoto || library.root == nil || library.preparingLibrary || library.activity != nil || editor.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (editor.isEditingBook && !editor.hasChanges))
                    .accessibilityIdentifier("save-book")
            }
            ToolbarItem(placement: .bottomBar) {
                Label(editor.saved ? "Changes kept on this device" : "Saving Draft…", systemImage: editor.saved ? "checkmark.circle" : "clock")
                    .labelStyle(.titleAndIcon).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .interactiveDismissDisabled()
        .task { await editor.loadBaseline() }
        .sheet(isPresented: $recordingFullBook) {
            RecordingView(text: editor.draft.chapters.map(\.text).joined(separator: "\n\n")) { await editor.setFullAudio($0) }
        }
        .sheet(isPresented: $creatingNarration) { NavigationStack { NarrationComposerView(editor: editor) } }
        .fileImporter(isPresented: $importingFullAudio, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): Task { _ = await editor.setFullAudio(url) }
            case .failure(let error):
                AppLog.error("Book recording selection failed", error: error, category: "creator", metadata: diagnosticFields)
                editor.message = error.localizedDescription
            }
        }
        .confirmationDialog("Remove this chapter?", isPresented: Binding(get: { removingChapter != nil }, set: { if !$0 { removingChapter = nil } }), titleVisibility: .visible) {
            Button("Remove Chapter", role: .destructive) {
                if let index = editor.draft.chapters.firstIndex(where: { $0.id == removingChapter }) { editor.deleteChapters(at: [index]) }
                removingChapter = nil
            }
        }
        .task(id: photo) {
            guard let photo else { return }
            loadingPhoto = true
            defer { loadingPhoto = false }
            AppLog.trace("Cover photo transfer started", category: "creator", metadata: diagnosticFields)
            do {
                if let data = try await photo.loadTransferable(type: Data.self) {
                    AppLog.trace("Cover photo transfer completed", category: "creator", metadata: diagnosticFields.merging(["byte_count": .integer(data.count)]) { _, new in new })
                    await editor.setImage(data)
                } else { AppLog.warning("Cover photo transfer returned no image data", category: "creator", metadata: diagnosticFields) }
            }
            catch is CancellationError { AppLog.trace("Cover photo loading cancelled", category: "creator", metadata: diagnosticFields) }
            catch {
                AppLog.error("Cover photo loading failed", error: error, category: "creator", metadata: diagnosticFields)
                editor.message = String(localized: "The photo could not be opened. Try another photo.")
            }
        }
        .onChange(of: phase) { _, new in
            if new != .active {
                AppLog.trace("Book editor scene background persistence requested", category: "creator", metadata: diagnosticFields)
                Task {
                    do { try await editor.persist() }
                    catch is CancellationError { AppLog.trace("Background draft save cancelled", category: "creator", metadata: diagnosticFields) }
                    catch {
                        AppLog.error("Background draft save failed", error: error, category: "creator", metadata: diagnosticFields)
                        editor.message = String(localized: "Your draft could not be saved. Keep the editor open and try again.")
                    }
                }
            }
        }
        .alert("Unable to complete", isPresented: Binding(get: { editor.message != nil }, set: { if !$0 { editor.message = nil } })) { } message: { Text(editor.message ?? "") }
        .alert("Book Changed", isPresented: $editor.conflict) {
            Button("Save as a New Book") { Task { await save(asCopy: true) } }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text(BookError.editConflict.localizedDescription) }
        .onDisappear { preview.stop() }
    }

    private func save(asCopy: Bool = false) async {
        if await editor.save(to: library, asCopy: asCopy) {
            library.showingCreator = false; library.editingDraft = nil
            dismiss()
        }
    }
}
