import SwiftUI

struct LibraryGridView: View {
    @Environment(LibraryModel.self) private var library
    let splitLayout: Bool
    var body: some View {
        @Bindable var library = library
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if library.preparingLibrary && !library.books.isEmpty { ProgressView("Opening your library…").frame(maxWidth: .infinity) }
                notes
                if (library.refreshing || library.preparingLibrary) && library.books.isEmpty {
                    VStack(spacing: 16) {
                        MoonIllustration(size: 60)
                        ProgressView("Opening your library…")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
                } else if library.books.isEmpty {
                    EmptyShelfView()
                } else if library.filteredBooks.isEmpty {
                    ContentUnavailableView.search
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 20, alignment: .top)], alignment: .leading, spacing: 32) {
                        ForEach(library.filteredBooks) { book in
                            if splitLayout {
                                Button { library.selectedBook = book } label: { BookGridCell(book: book, selected: library.selectedBook?.id == book.id) }
                                    .buttonStyle(.pressable)
                                    .accessibilityIdentifier("book-" + book.id.uuidString)
                                    .contextMenu { BookActionsMenu(book: book) }
                            } else {
                                NavigationLink(value: book) { BookGridCell(book: book) }.buttonStyle(.pressable)
                                    .accessibilityIdentifier("book-" + book.id.uuidString)
                                    .contextMenu { BookActionsMenu(book: book) }
                            }
                        }
                    }
                    Text("\(library.books.count) books").font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background { StoryBackground() }
        .navigationTitle("Library")
        .navigationSubtitle(greeting)
        .searchable(text: $library.search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a story")
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

    @ViewBuilder private var notes: some View {
        if library.offline {
            NoteCard(systemImage: "icloud.slash", text: Text("Folder unavailable. Downloaded content remains available.")) {
                Button("Retry Library Setup") { Task { await library.start() } }
            }
        }
        if !library.cloudStorage {
            NoteCard(systemImage: "iphone", text: Text("Books are stored on this device. Turn on iCloud Drive in Settings to sync them across your devices."))
        }
        if let message = library.migrationMessage {
            NoteCard(systemImage: "arrow.triangle.2.circlepath", text: Text(message)) {
                Button("Retry Library Setup") { Task { await library.start() } }
            }
        }
        if !library.warnings.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(library.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                .padding(.top, 8)
            } label: {
                Label("Some books need attention", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
            }
            .storyCard(padding: 16, cornerRadius: 20)
        }
    }

    private var greeting: Text {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: Text("Good morning")
        case 12..<17: Text("Good afternoon")
        case 17..<21: Text("Good evening")
        default: Text("Time for sweet dreams")
        }
    }
}

/// A friendly first shelf: a few illustrated books and two clear ways to begin.
private struct EmptyShelfView: View {
    @Environment(LibraryModel.self) private var library
    private let samples = ["55555555-5555-4555-8555-555555555555", "11111111-1111-4111-8111-111111111111", "33333333-3333-4333-8333-333333333333"].compactMap(UUID.init(uuidString:))

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, id in
                    CoverArtwork(id: id)
                        .frame(width: 92, height: 138)
                        .bookStyle(width: 92)
                        .rotationEffect(.degrees(Double(index - 1) * 10), anchor: .bottom)
                        .offset(x: CGFloat(index - 1) * 52, y: index == 1 ? -8 : 4)
                        .zIndex(index == 1 ? 1 : 0)
                }
            }
            .frame(height: 170)
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Your bookshelf is ready").storyFont(.title2, weight: .bold).foregroundStyle(Theme.ink)
                Text("Create a book with your own words and voice, or import a .bedtimestory book.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                Button("Create a Book", systemImage: "square.and.pencil", action: library.createBook)
                    .buttonStyle(.storyProminent(fullWidth: true))
                Button("Import Book", systemImage: "square.and.arrow.down") { library.showingImportPicker = true }
                    .buttonStyle(.storySoft(fullWidth: true))
            }
            .frame(maxWidth: 360)
        }
        .padding(.vertical, 32).padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}
