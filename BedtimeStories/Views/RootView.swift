import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(OperationCenter.self) private var operations
    @Environment(CloudNarrationModel.self) private var cloud
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bookPath: [LibraryBook] = []
    @State private var showingVoices = false
    @State private var suspendedImportReview = false
    @State private var rootPresentationVisible = false
    @State private var pendingDestination: OperationDestination?
    @State private var pendingOwnerGeneration: UUID?
    @State private var resolvingDestination = false
    @State private var initialNarrationDraftID: UUID?
    @State private var narrationRecovery: NarrationRecoveryTarget?
    #if DEBUG || MZ_INTERNAL
    @State private var seededOperationQA = false
    #endif

    var body: some View {
        @Bindable var library = library
        @Bindable var operations = operations
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
                NavigationStack(path: $bookPath) {
                    LibraryGridView(splitLayout: false)
                        .navigationDestination(for: LibraryBook.self) { BookDetailView(book: $0) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !operations.activeOperations.isEmpty && library.root != nil {
                    OperationStatusView()
                        .frame(maxWidth: 600)
                        .padding(.horizontal)
                        .padding(.bottom, library.player.book == nil ? 8 : 0)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else if let activity = library.activity {
                    HStack(spacing: 12) {
                        ProgressView().tint(Theme.accent)
                        Text(activity).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                if library.player.book != nil && library.root != nil {
                    MiniPlayerView().padding(.horizontal).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: library.player.book?.id)
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: operations.activeOperations.count)
        }
        .operationFeedback()
        .sheet(isPresented: $library.showingSettings, onDismiss: presentationDismissed) {
            NavigationStack { SettingsView() }
                .operationFeedback()
                .onAppear { rootPresentationVisible = true }
        }
        .sheet(isPresented: $library.showingCreator, onDismiss: presentationDismissed) {
            BookCreatorView()
                .operationFeedback()
                .onAppear { rootPresentationVisible = true }
        }
        .sheet(item: $library.editingDraft, onDismiss: presentationDismissed) { draft in
            NavigationStack { BookEditorView(draft: draft, store: .shared, initiallyShowNarration: initialNarrationDraftID == draft.id) }
                .operationFeedback()
                .onAppear { rootPresentationVisible = true }
        }
        .fullScreenCover(isPresented: $library.showingPlayer, onDismiss: presentationDismissed) {
            NowPlayingView()
                .operationFeedback()
                .onAppear { rootPresentationVisible = true }
        }
        .sheet(item: Binding(get: { suspendedImportReview ? nil : library.importCandidate }, set: { if !suspendedImportReview { library.importCandidate = $0 } }), onDismiss: presentationDismissed) { candidate in
            ImportReviewView(book: candidate)
                .interactiveDismissDisabled()
                .operationFeedback()
                .onAppear { rootPresentationVisible = true }
        }
        .sheet(isPresented: $operations.showingOperations, onDismiss: presentationDismissed) {
            NavigationStack {
                OperationsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { operations.showingOperations = false } } }
            }
            .operationFeedback()
            .onAppear { rootPresentationVisible = true }
        }
        .sheet(isPresented: $showingVoices, onDismiss: presentationDismissed) {
            NavigationStack {
                YourVoicesView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingVoices = false } } }
            }
            .operationFeedback()
            .onAppear { rootPresentationVisible = true }
        }
        .sheet(item: $narrationRecovery, onDismiss: presentationDismissed) { target in
            NavigationStack { NarrationRecoveryView(target: target) }
                .operationFeedback()
                .onAppear { rootPresentationVisible = true }
        }
        .sheet(isPresented: Binding(get: { library.shareURL != nil && !library.showingPlayer }, set: { if !$0 { library.shareURL = nil } }), onDismiss: presentationDismissed) {
            if let url = library.shareURL {
                ShareSheet(url: url)
                    .operationFeedback()
                    .onAppear { rootPresentationVisible = true }
            }
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
        .task {
            await library.start()
            #if DEBUG || MZ_INTERNAL
            seedOperationQAIfRequested()
            #endif
            if let destination = operations.requestedDestination { receiveDestination(destination) }
        }
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
                suspendedImportReview = false
                AppLog.debug("Book import review presented", category: "navigation", metadata: ["book_id": .string(current.uuidString)])
            }
        }
        .onChange(of: library.message != nil) { _, presented in
            AppLog.debug(presented ? "Library failure alert presented" : "Library failure alert dismissed", category: "navigation")
        }
        .onChange(of: operations.requestedDestination) { _, destination in
            if let destination { receiveDestination(destination) }
        }
        .onChange(of: operations.ownerGeneration) { _, _ in
            pendingDestination = nil
            pendingOwnerGeneration = nil
            narrationRecovery = nil
        }
        .onOpenURL { url in
            // Developer links belong to the foundation modifier; only file URLs are books.
            if url.isFileURL {
                AppLog.debug("Book file opened externally", category: "navigation", metadata: ["source": .string("open_url")])
                library.importBook(url)
            } else {
                _ = operations.handle(url)
            }
        }
    }

    /// Dismiss the current surface first; opening another sheet before its
    /// dismissal finishes can otherwise silently drop a notification tap.
    private func receiveDestination(_ destination: OperationDestination) {
        pendingDestination = destination
        pendingOwnerGeneration = operations.ownerGeneration
        operations.consumeDestination()
        library.showingSettings = false
        library.showingCreator = false
        library.editingDraft = nil
        library.showingPlayer = false
        library.showingImportPicker = false
        library.shareURL = nil
        showingVoices = false
        narrationRecovery = nil
        operations.showingOperations = false
        if library.importCandidate != nil { suspendedImportReview = true }
        if !rootPresentationVisible { resolvePendingDestination() }
    }

    private func presentationDismissed() {
        rootPresentationVisible = false
        initialNarrationDraftID = nil
        resolvePendingDestination()
    }

    private func resolvePendingDestination() {
        guard pendingDestination != nil, !resolvingDestination else { return }
        resolvingDestination = true
        Task {
            defer {
                resolvingDestination = false
                if pendingDestination != nil && !rootPresentationVisible { resolvePendingDestination() }
            }
            guard let destination = pendingDestination, let generation = pendingOwnerGeneration else { return }
            pendingDestination = nil
            pendingOwnerGeneration = nil
            guard generation == operations.ownerGeneration else { return }
            switch destination {
            case .book(let id):
                if !library.books.contains(where: { $0.id == id }) {
                    await library.start()
                    guard generation == operations.ownerGeneration else { return }
                    await library.refresh()
                }
                guard generation == operations.ownerGeneration else { return }
                guard let book = library.books.first(where: { $0.id == id }) else {
                    operations.message = String(localized: "This book is not available yet. Check your library and try again.")
                    return
                }
                library.search = ""
                library.selectedBook = book
                bookPath = [book]
            case .draft(let id), .narration(let id):
                do {
                    let draft = try await BookDraftStore.shared.load(id)
                    guard generation == operations.ownerGeneration else { return }
                    if case .narration = destination { initialNarrationDraftID = id }
                    else { initialNarrationDraftID = nil }
                    library.editingDraft = draft
                } catch {
                    guard generation == operations.ownerGeneration else { return }
                    if NarrationRecoveryTarget.isMissingDraft(error), let owner = cloud.userID,
                       let target = NarrationRecoveryTarget.select(destination: destination, ownerID: owner,
                           currentOwnerID: operations.currentOwnerID, jobs: cloud.jobs) ??
                           NarrationRecoveryTarget.selectReceipt(destination: destination, ownerID: owner,
                               currentOwnerID: operations.currentOwnerID, operations: operations.operations) {
                        AppLog.trace("Missing narration draft opened as listen-only recovery", category: "navigation", metadata: ["draft_id": .string(id.uuidString)])
                        narrationRecovery = target
                    } else if NarrationRecoveryTarget.isMissingDraft(error) {
                        AppLog.trace("Missing operation draft redirected to operations", category: "navigation", metadata: ["draft_id": .string(id.uuidString)])
                        // Keep old receipts useful without repeatedly routing to a deleted draft.
                        for operation in operations.visibleOperations where operation.destination == .draft(id) || operation.destination == .narration(id) {
                            operations.update(operation.id, destination: .operations)
                        }
                        operations.showingOperations = true
                        operations.message = String(localized: "This draft is no longer on this device. Open the book from your library to create narration again.")
                    } else {
                        AppLog.error("Operation result draft could not be opened", error: error, category: "navigation", metadata: ["draft_id": .string(id.uuidString)])
                        operations.message = String(localized: "This draft could not be opened. It may have already been saved to your library.")
                    }
                }
            case .voices:
                showingVoices = true
            case .operations:
                operations.showingOperations = true
            case .importReview:
                if library.importCandidate != nil {
                    suspendedImportReview = false
                } else {
                    operations.showingOperations = true
                    operations.message = String(localized: "This import is no longer waiting for review.")
                }
            }
        }
    }

    #if DEBUG || MZ_INTERNAL
    private func seedOperationQAIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-operations"), !seededOperationQA, let book = library.books.first else { return }
        seededOperationQA = true
        let activeID = operations.begin(kind: .narration, title: book.manifest.title,
            subtitle: String(localized: "Creating narration"), destination: .book(book.id), id: "qa-active-narration", progress: 0.42)
        operations.update(activeID, state: .running, progress: 0.42, destination: .book(book.id), title: book.manifest.title)
        let readyID = operations.begin(kind: .storyGeneration, title: "The Fox and the Stars",
            subtitle: String(localized: "Your story draft is ready"), destination: .book(book.id), id: "qa-ready-story")
        operations.update(readyID, state: .ready, progress: 1, destination: .book(book.id))
        if arguments.contains("--qa-operation-banner") {
            operations.banner = operations.operations.first { $0.id == readyID }
        } else {
            operations.dismissBanner()
        }
    }
    #endif
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
