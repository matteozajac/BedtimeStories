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
                        else { ContentUnavailableView("Choose a book", systemImage: "books.vertical", description: Text("Your next bedtime story is waiting in the library.")) }
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
            if library.player.book != nil && library.root != nil { MiniPlayerView().padding(.horizontal).padding(.bottom, 8) }
        }
        .overlay(alignment: .top) {
            if let activity = library.activity {
                HStack {
                    ProgressView()
                    Text(activity).font(.subheadline)
                    Button("Cancel", action: library.cancelOperation)
                }
                .padding().background(.regularMaterial, in: .capsule).padding()
                .accessibilityElement(children: .contain)
            }
        }
        .sheet(isPresented: $library.showingSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: $library.showingPlayer) { NowPlayingView() }
        .sheet(item: $library.importCandidate) { candidate in
            ImportReviewView(book: candidate).interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(get: { library.shareURL != nil && !library.showingPlayer }, set: { if !$0 { library.shareURL = nil } })) {
            if let url = library.shareURL { ShareSheet(url: url) }
        }
        .fileImporter(isPresented: $library.showingFolderPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await library.selectFolder(url) }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $library.showingImportPicker, allowedContentTypes: [UTType(exportedAs: "com.matteozajac.bedtimestories.book"), .zip]) { result in
            switch result {
            case .success(let url): library.importBook(url)
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .alert("Unable to complete", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK") { library.message = nil }
        } message: { Text(library.message ?? "") }
        .task { await library.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.refresh() } }
        }
        .onOpenURL { library.importBook($0) }
    }
}
