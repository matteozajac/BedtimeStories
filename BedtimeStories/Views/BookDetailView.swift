import SwiftUI

struct BookDetailView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var body: some View {
        let book = library.books.first(where: { $0.id == self.book.id }) ?? self.book
        ScrollView {
            VStack(spacing: 24) {
                BookCoverView(book: book).aspectRatio(2.0 / 3.0, contentMode: .fit).frame(maxWidth: 220)
                VStack(spacing: 8) {
                    Text(book.manifest.title).font(.largeTitle.bold()).fontDesign(.serif).multilineTextAlignment(.center)
                    if let author = book.manifest.author { Text(author).font(.title3).foregroundStyle(.secondary) }
                }
                if let description = book.manifest.description { Text(description).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                if book.manifest.hasAudio {
                    Button(library.progress.playback(book.id) == nil ? "Listen" : "Resume", systemImage: "play.fill") { library.listen(book) }
                        .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("listen-book")
                }
                if book.manifest.hasReading {
                    NavigationLink { ReaderView(book: book) } label: { Label("Read", systemImage: "book") }
                        .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("read-book")
                }
                if !book.manifest.hasAudio && !book.manifest.hasReading {
                    ContentUnavailableView("A story waiting to happen", systemImage: "moon", description: Text("Text, pictures, and recordings can be added to this book’s folder whenever you’re ready."))
                }
                if !book.manifest.orderedChapters.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Chapters").font(.title2.bold()).fontDesign(.serif).padding(.bottom)
                        ForEach(Array(book.manifest.orderedChapters.enumerated()), id: \.element.id) { index, chapter in
                            ChapterRow(book: book, chapter: chapter, number: index + 1)
                            Divider()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .navigationTitle(book.manifest.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { BookActionsMenu(book: book) } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Book actions")
            }
        }
    }
}
