import SwiftUI

struct BookCreatorView: View {
    @Environment(CloudNarrationModel.self) private var cloud
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
                    CreatorOption(title: "Create from an Idea", subtitle: "Describe a story and choose Gemini or Apple Intelligence to write it.", systemImage: "sparkles", magical: true) {
                        path.append(BookCreatorRoute.storyIdea)
                    }
                    .accessibilityIdentifier("create-book-from-idea")
                    CreatorOption(title: "Create a Book", subtitle: "Write it yourself, add pictures, and record your voice.", systemImage: "square.and.pencil") {
                        Task {
                            AppLog.trace("Draft creation started", category: "creator")
                            do {
                                let draft = try await store.create()
                                await store.flushDiagnosticLogs()
                                AppLog.debug("Draft creation completed", category: "creator", metadata: ["draft_id": .string(draft.id.uuidString)])
                                path.append(draft)
                            }
                            catch is CancellationError { AppLog.trace("Draft creation cancelled", category: "creator") }
                            catch {
                                AppLog.error("Draft creation failed", error: error, category: "creator")
                                message = String(localized: "A draft could not be created. Free some space on this device and try again.")
                            }
                        }
                    }
                    .accessibilityIdentifier("new-book-draft")
                } footer: {
                    Text("Write a story, add pictures, and record it in your own voice. Your work is kept on this device; Save adds the book to your library.")
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                Section("Your Drafts") {
                    if loading { ProgressView("Opening drafts…") }
                    else if drafts.isEmpty {
                        Label { Text("Your next story starts here.").foregroundStyle(.secondary) } icon: { Image(systemName: "moon.stars").foregroundStyle(Theme.glow) }
                    }
                    ForEach(drafts) { draft in
                        NavigationLink(value: draft) {
                            HStack(spacing: 14) {
                                DraftCoverView(draft: draft, store: store).frame(width: 46, height: 69)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(draft.title.isEmpty ? String(localized: "Untitled Book") : draft.title)
                                        .storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink).lineLimit(2)
                                    if draft.source != nil {
                                        Label("Editing a library book", systemImage: "pencil").font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                                            .labelStyle(CompactLabelStyle())
                                    }
                                    Text(draft.modifiedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { deleting = draft } }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .storyFormStyle()
            .navigationTitle("Book Creator")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .navigationDestination(for: BookDraft.self) { BookEditorView(draft: $0, store: store) }
            .navigationDestination(for: BookCreatorRoute.self) { _ in
                StoryIdeaView(store: store, cloud: cloud) { draft in
                    path = NavigationPath([draft])
                }
            }
            .task { await reload() }
            .onChange(of: path.isEmpty) { _, empty in if empty { Task { await reload() } } }
            .alert("Delete this draft?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete Draft", role: .destructive) {
                    guard let draft = deleting else { return }
                    Task {
                        do {
                            try await store.remove(draft.id)
                            await store.flushDiagnosticLogs()
                            deleting = nil; await reload()
                        }
                        catch {
                            AppLog.error("Draft deletion failed", error: error, category: "creator", metadata: ["draft_id": .string(draft.id.uuidString)])
                            message = String(localized: "The draft could not be deleted. Try again.")
                        }
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Its text, pictures, and recordings will be removed from this device.") }
            .alert("Unable to complete", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { } message: { Text(message ?? "") }
        }
    }

    private func reload() async {
        AppLog.trace("Draft listing started", category: "creator")
        do {
            drafts = try await store.list()
            AppLog.debug("Draft listing completed", category: "creator", metadata: ["draft_count": .integer(drafts.count)])
        }
        catch is CancellationError { AppLog.trace("Draft listing cancelled", category: "creator") }
        catch {
            AppLog.error("Draft listing failed", error: error, category: "creator")
            message = String(localized: "Your drafts could not be opened. Try again.")
        }
        loading = false
    }
}

/// A large tappable card for one way to start a book. The magical variant is a small night sky.
private struct CreatorOption: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    var magical = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(magical ? Color(hex: 0xF5C77E) : Theme.accent)
                    .symbolEffect(.breathe, isActive: magical)
                    .frame(width: 56, height: 56)
                    .background(magical ? Color.white.opacity(0.12) : Theme.accentSoft, in: .rect(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).storyFont(.title3, weight: .semibold).foregroundStyle(magical ? Theme.moonlight : Theme.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(magical ? Theme.moonlight.opacity(0.75) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                    .foregroundStyle(magical ? Theme.moonlight.opacity(0.6) : Color.secondary)
            }
            .padding(18)
            .background {
                if magical {
                    NightCardBackground()
                } else {
                    RoundedRectangle(cornerRadius: 24).fill(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.surfaceStroke))
                }
            }
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.pressable)
    }
}
