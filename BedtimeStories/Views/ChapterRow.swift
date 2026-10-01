import SwiftUI

struct ChapterRow: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    let chapter: BookChapter
    let number: Int
    var body: some View {
        HStack(spacing: 16) {
            Text(number, format: .number).font(.subheadline).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            if chapter.text != nil || chapter.image != nil {
                NavigationLink { ReaderView(book: book, startingChapter: chapter.id) } label: {
                    Text(chapter.title ?? String(localized: "Chapter \(number)")).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).frame(minHeight: 44)
            } else {
                Text(chapter.title ?? String(localized: "Chapter \(number)")).frame(maxWidth: .infinity, alignment: .leading)
            }
            if chapter.audio != nil || (book.manifest.audio != nil && chapter.startTime != nil) {
                Button("Play chapter", systemImage: "play.circle") { library.listen(book, chapter: chapter) }
                    .labelStyle(.iconOnly).font(.title2).frame(minWidth: 44, minHeight: 44)
            }
        }.padding(.vertical, 8)
    }
}
