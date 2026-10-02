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
                if editor.draft.cover != nil { Button("Remove Cover", role: .destructive) { editor.draft.cover = nil } }
            }
            Section {
                ForEach(editor.draft.chapters.enumerated(), id: \.element.id) { number, chapter in
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
                }
                .onDelete(perform: editor.deleteChapters)
                .onMove(perform: editor.moveChapters)
                Button("Add Chapter", systemImage: "plus", action: editor.addChapter).accessibilityIdentifier("add-draft-chapter")
            } header: { Text("Chapters") } footer: { Text("Open a chapter to write, add a picture, or record narration. Use Edit to reorder or remove chapters.") }
            Section {
                Button("Add to Library", systemImage: "books.vertical") { Task { await editor.publish(to: library) } }
                    .disabled(library.root == nil || library.preparingLibrary || editor.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.activity != nil)
                    .accessibilityIdentifier("publish-book")
            } footer: {
                Text("Add the finished book to your library to read, listen, and share it with your family.")
            }
            if editor.working || loadingPhoto { ProgressView("Saving…") }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(editor.working || loadingPhoto)
        .navigationTitle("Create Book").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .navigationDestination(for: UUID.self) { ChapterEditorView(editor: editor, chapterID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Save Draft") { Task { if await editor.close() { dismiss() } } }.disabled(editor.working || loadingPhoto)
                    .accessibilityIdentifier("save-book-draft")
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(editor.working || loadingPhoto) }
            ToolbarItem(placement: .bottomBar) {
                Label(editor.saved ? "Draft Saved" : "Saving Draft…", systemImage: editor.saved ? "checkmark.circle" : "clock")
                    .labelStyle(.titleAndIcon).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .interactiveDismissDisabled()
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
    }
}
