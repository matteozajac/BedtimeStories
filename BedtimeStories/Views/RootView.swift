import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var library = library
        Group {
            if library.root == nil {
                NavigationStack { FolderWelcomeView() }
            } else if sizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView {
                    LibraryGridView(splitLayout: true)
                        .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 600)
                } detail: {
                    NavigationStack {
                        if let book = library.selectedBook { BookDetailView(book: book).id(book.id) }
                        else { ChooseBookView() }
                    }
                }
            } else {
                NavigationStack {
                    LibraryGridView(splitLayout: false)
                        .navigationDestination(for: LibraryBook.self) { BookDetailView(book: $0) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                if library.player.book != nil && library.root != nil {
                    MiniPlayerView().padding(.horizontal).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.45), value: library.player.book?.id)
        }
        .overlay(alignment: .top) {
            VStack {
                if let activity = library.activity {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(activity).font(.subheadline.weight(.medium))
                        Button("Cancel") {
                            AppLog.debug("Library operation cancellation selected", category: "navigation")
                            library.cancelOperation()
                        }.font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                }
            }
            .animation(.spring(duration: 0.4), value: library.activity)
        }
        .sheet(isPresented: $library.showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $library.showingCreator) { BookCreatorView() }
        .sheet(item: $library.editingDraft) { draft in
            NavigationStack { BookEditorView(draft: draft, store: .shared) }
        }
        .fullScreenCover(isPresented: $library.showingPlayer) { NowPlayingView() }
        .sheet(item: $library.importCandidate) { candidate in
            ImportReviewView(book: candidate).interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(get: { library.shareURL != nil && !library.showingPlayer }, set: { if !$0 { library.shareURL = nil } })) {
            if let url = library.shareURL { ShareSheet(url: url) }
        }
        .fileImporter(isPresented: $library.showingImportPicker, allowedContentTypes: [UTType(exportedAs: "com.matteozajac.bedtimestories.book"), .zip]) { result in
            switch result {
            case .success(let url):
                AppLog.debug("Book document selected", category: "navigation", metadata: [
                    "source": .string("document_picker"), "file_type": .string(url.pathExtension.lowercased() == "zip" ? "zip" : "bedtimestory")
                ])
                library.importBook(url)
            case .failure(let error):
                let failure = error as NSError
                if failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError {
                    AppLog.trace("Book document selection cancelled", category: "navigation")
                    return
                }
                AppLog.error("Document selection failed", error: error, category: "library")
                library.message = error.localizedDescription
            }
        }
        .alert("Unable to complete", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK") { library.message = nil }
        } message: { Text(library.message ?? "") }
        .task { await library.start() }
        .onChange(of: scenePhase) { _, phase in
            let state: String
            switch phase {
            case .active: state = "active"
            case .inactive: state = "inactive"
            case .background: state = "background"
            @unknown default: state = "unknown"
            }
            AppLog.debug("Application scene state changed", category: "app", metadata: ["state": .string(state)])
            if phase == .active { Task { await library.start() } }
        }
        .onChange(of: library.showingSettings) { _, presented in
            AppLog.debug(presented ? "Settings opened" : "Settings closed", category: "navigation")
        }
        .onChange(of: library.showingCreator) { _, presented in
            AppLog.debug(presented ? "Book creator opened" : "Book creator closed", category: "navigation")
        }
        .onChange(of: library.editingDraft?.id) { previous, current in
            if let current {
                AppLog.debug("Book editor presented", category: "navigation", metadata: ["draft_id": .string(current.uuidString)])
            } else if let previous {
                AppLog.debug("Book editor dismissed", category: "navigation", metadata: ["draft_id": .string(previous.uuidString)])
            }
        }
        .onChange(of: library.showingPlayer) { _, presented in
            AppLog.debug(presented ? "Now Playing opened" : "Now Playing closed", category: "navigation")
        }
        .onChange(of: library.showingImportPicker) { _, presented in
            AppLog.trace(presented ? "Book document picker opened" : "Book document picker closed", category: "navigation")
        }
        .onChange(of: library.importCandidate?.id) { _, current in
            if let current {
                AppLog.debug("Book import review presented", category: "navigation", metadata: ["book_id": .string(current.uuidString)])
            }
        }
        .onChange(of: library.message != nil) { _, presented in
            AppLog.debug(presented ? "Library failure alert presented" : "Library failure alert dismissed", category: "navigation")
        }
        .onOpenURL { url in
            // Developer links belong to the foundation modifier; only file URLs are books.
            if url.isFileURL {
                AppLog.debug("Book file opened externally", category: "navigation", metadata: ["source": .string("open_url")])
                library.importBook(url)
            }
        }
    }
}

/// The iPad detail pane before a book is chosen.
private struct ChooseBookView: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.glow.opacity(0.18)).frame(width: 150, height: 150).blur(radius: 20)
                Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(Theme.glow).symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
            Text("Choose a book").storyFont(.title, weight: .bold).foregroundStyle(Theme.ink)
            Text("Your next bedtime story is waiting in the library.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { StoryBackground() }
    }
}
