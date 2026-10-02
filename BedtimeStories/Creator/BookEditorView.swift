import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BookEditorView: View {
    @Environment(LibraryModel.self) private var library
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

    init(draft: BookDraft, store: BookDraftStore) {
        _editor = State(initialValue: BookEditorModel(draft: draft, store: store))
    }

    var body: some View {
        @Bindable var editor = editor
        let hasCover = editor.draft.cover != nil
        Form {
            Section("Book Details") {
                TextField("Book title", text: $editor.draft.title).accessibilityIdentifier("draft-title")
                TextField("Author (optional)", text: $editor.draft.author).textContentType(.name)
                TextField("About this story (optional)", text: $editor.draft.summary, axis: .vertical).lineLimit(3...6)
                DraftImageView(path: editor.draft.cover, draftID: editor.draft.id, store: editor.store)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(hasCover ? "Change Cover Photo" : "Add Cover Photo", systemImage: "photo")
                }.disabled(loadingPhoto || editor.working)
                BookIllustrationButton(editor: editor)
                if editor.draft.cover != nil { Button("Remove Cover", role: .destructive) { editor.draft.cover = nil } }
            }
            Section("Reading Time") {
                LabeledContent("Words", value: editor.draft.wordCount.formatted())
                Stepper("Reading pace: \(editor.readingPace) words/minute", value: $editor.readingPace, in: 80...180, step: 10)
                Text("About \(StoryReadingLength.minutes(words: editor.draft.wordCount, wordsPerMinute: editor.readingPace).formatted(.number.precision(.fractionLength(1)))) minutes for the whole book.")
                    .accessibilityIdentifier("book-estimated-reading-time")
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
            }
            Section {
                ForEach(editor.draft.chapters.enumerated(), id: \.element.id) { number, chapter in
                    HStack {
                      NavigationLink(value: chapter.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chapter.title.isEmpty ? String(localized: "Chapter \(number + 1)") : chapter.title).font(.headline)
                            HStack {
                                if !chapter.text.isEmpty { Label("Text", systemImage: "text.alignleft") }
                                if chapter.image != nil { Label("Picture", systemImage: "photo") }
                                if chapter.audio != nil { Label("Narration", systemImage: "waveform") }
                                if chapter.text.isEmpty && chapter.image == nil && chapter.audio == nil { Text("Ready for your story") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
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
                Button("Add Chapter", systemImage: "plus", action: editor.addChapter).accessibilityIdentifier("add-draft-chapter")
            } header: { Text("Chapters") } footer: { Text("Open a chapter to write, add a picture, or record narration. Chapter Options lets you reorder or remove chapters.") }
            Section {
                Text(editor.isEditingBook ? "Save updates this book in your library. Discard leaves the library version unchanged." : "Save adds this book to your library to read, listen, and share with your family.")
            }
            if editor.working || loadingPhoto { ProgressView("Saving…") }
        }
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
        .fileImporter(isPresented: $importingFullAudio, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): Task { _ = await editor.setFullAudio(url) }
            case .failure(let error): editor.message = error.localizedDescription
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
            do { if let data = try await photo.loadTransferable(type: Data.self) { await editor.setImage(data) } }
            catch { editor.message = String(localized: "The photo could not be opened. Try another photo.") }
        }
        .onChange(of: phase) { _, new in
            if new != .active { Task { do { try await editor.persist() } catch { editor.message = String(localized: "Your draft could not be saved. Keep the editor open and try again.") } } }
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
