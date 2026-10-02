import SwiftUI

struct BookCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [BookDraft] = []
    @State private var path = NavigationPath()
    @State private var loading = true
    @State private var message: String?
    @State private var deleting: BookDraft?
    private let store = BookDraftStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: BookCreatorRoute.storyIdea) {
                        Label("Create from an Idea", systemImage: "sparkles")
                    }
                        .accessibilityIdentifier("create-book-from-idea")
                    Button("Create a Book", systemImage: "square.and.pencil") {
                        Task {
                            do { let draft = try await store.create(); path.append(draft) }
                            catch { message = String(localized: "A draft could not be created. Free some space on this device and try again.") }
                        }
                    }.accessibilityIdentifier("new-book-draft")
                } footer: {
                    Text("Write a story, add pictures, and record it in your own voice. Your work is kept on this device; Save adds the book to your library.")
                }
                Section("Your Drafts") {
                    if loading { ProgressView("Opening drafts…") }
                    else if drafts.isEmpty { Text("Your next story starts here.").foregroundStyle(.secondary) }
                    ForEach(drafts) { draft in
                        NavigationLink(value: draft) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(draft.title.isEmpty ? String(localized: "Untitled Book") : draft.title).font(.headline)
                                if draft.source != nil { Text("Editing a library book").font(.caption).foregroundStyle(.secondary) }
                                Text(draft.modifiedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { deleting = draft } }
                    }
                }
            }
            .navigationTitle("Book Creator")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .navigationDestination(for: BookDraft.self) { BookEditorView(draft: $0, store: store) }
            .navigationDestination(for: BookCreatorRoute.self) { _ in
                StoryIdeaView(store: store) { draft in
                    path = NavigationPath([draft])
                }
            }
            .task { await reload() }
            .onChange(of: path.isEmpty) { _, empty in if empty { Task { await reload() } } }
            .alert("Delete this draft?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete Draft", role: .destructive) {
                    guard let draft = deleting else { return }
                    Task {
                        do { try await store.remove(draft.id); deleting = nil; await reload() }
                        catch { message = String(localized: "The draft could not be deleted. Try again.") }
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Its text, pictures, and recordings will be removed from this device.") }
            .alert("Unable to complete", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { } message: { Text(message ?? "") }
        }
    }

    private func reload() async {
        do { drafts = try await store.list() }
        catch { message = String(localized: "Your drafts could not be opened. Try again.") }
        loading = false
    }
}
