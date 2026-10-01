import SwiftUI

struct BookGridCell: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BookCoverView(book: book)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
            Text(book.manifest.title).font(.headline).fontDesign(.serif).foregroundStyle(.primary).lineLimit(2)
            if let author = book.manifest.author { Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            HStack {
                if book.manifest.hasAudio { Image(systemName: "headphones").accessibilityLabel("Audiobook") }
                if book.manifest.hasReading { Image(systemName: "text.book.closed").accessibilityLabel("Readable book") }
                Spacer()
                if library.pinned.contains(book.id) { Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Kept offline") }
            }.font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
