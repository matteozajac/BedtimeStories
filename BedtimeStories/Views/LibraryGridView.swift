import SwiftUI

struct LibraryGridView: View {
    @Environment(LibraryModel.self) private var library
    let splitLayout: Bool
    var body: some View {
        @Bindable var library = library
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if library.preparingLibrary { ProgressView("Opening your library…") }
                if library.offline {
                    Label("Folder unavailable. Downloaded content remains available.", systemImage: "icloud.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Retry Library Setup") { Task { await library.start() } }
                }
                if !library.cloudStorage {
                    Label("Books are stored on this device. Turn on iCloud Drive in Settings to sync them across your devices.", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message = library.migrationMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry Library Setup") { Task { await library.start() } }
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
                        Text("Create a book with your own words and voice, or import a .bedtimestory book.")
                    } actions: {
                        Button("Create a Book", systemImage: "square.and.pencil", action: library.createBook)
                            .buttonStyle(.borderedProminent)
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
                Button("Create a Book", systemImage: "plus", action: library.createBook)
                    .accessibilityIdentifier("create-book").disabled(library.activity != nil || library.preparingLibrary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Book Creator", systemImage: "square.and.pencil", action: library.createBook)
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
