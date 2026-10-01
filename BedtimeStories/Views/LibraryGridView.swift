import SwiftUI

struct LibraryGridView: View {
    @Environment(LibraryModel.self) private var library
    let splitLayout: Bool
    var body: some View {
        @Bindable var library = library
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if library.offline {
                    Label("Folder unavailable. Downloaded content remains available.", systemImage: "icloud.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Choose Folder Again") { library.showingFolderPicker = true }
                }
                if !library.warnings.isEmpty {
                    DisclosureGroup {
                        ForEach(library.warnings, id: \.self) { Text($0).font(.footnote).textSelection(.enabled) }
                    } label: {
                        Label("Some books need attention", systemImage: "exclamationmark.triangle").font(.subheadline)
                    }
                }
                if library.refreshing && library.books.isEmpty {
                    ProgressView("Opening your library…").frame(maxWidth: .infinity).padding(.vertical, 80)
                } else if library.books.isEmpty {
                    ContentUnavailableView {
                        Label("Your bookshelf is ready", systemImage: "books.vertical")
                    } description: {
                        Text("Add book folders in Files or import a .bedtimestory book. A title is all a book needs to begin.")
                    } actions: {
                        Button("Import Book", systemImage: "square.and.arrow.down") { library.showingImportPicker = true }
                            .buttonStyle(.bordered)
                    }
                } else if library.filteredBooks.isEmpty {
                    ContentUnavailableView.search
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 230), spacing: 24)], alignment: .leading, spacing: 28) {
                        ForEach(library.filteredBooks) { book in
                            if splitLayout {
                                Button { library.selectedBook = book } label: { BookGridCell(book: book) }.buttonStyle(.plain)
                                    .accessibilityIdentifier("book-" + book.id.uuidString)
                                    .contextMenu { BookActionsMenu(book: book) }
                            } else {
                                NavigationLink(value: book) { BookGridCell(book: book) }.buttonStyle(.plain)
                                    .accessibilityIdentifier("book-" + book.id.uuidString)
                                    .contextMenu { BookActionsMenu(book: book) }
                            }
                        }
                    }
                    Text("\(library.books.count) books").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .navigationTitle("Library")
        .searchable(text: $library.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a story")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import Book", systemImage: "square.and.arrow.down") { library.showingImportPicker = true }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await library.refresh() } }
                    Button("Settings", systemImage: "gearshape") { library.showingSettings = true }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Library actions").accessibilityIdentifier("library-actions")
            }
        }
        .refreshable { await library.refresh() }
    }
}
