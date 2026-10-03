import SwiftUI

struct BookActionsMenu: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var body: some View {
        Button("Edit Book", systemImage: "square.and.pencil") {
            AppLog.debug("Edit Book selected", category: "navigation", metadata: [
                "book_id": .string(book.id.uuidString), "chapter_count": .integer(book.manifest.orderedChapters.count),
                "icloud": .bool(library.cloudStorage), "kept_offline": .bool(library.pinned.contains(book.id))
            ])
            library.editBook(book)
        }
            .accessibilityIdentifier("edit-library-book")
        Button("Share Book", systemImage: "square.and.arrow.up") {
            AppLog.debug("Share Book selected", category: "navigation", metadata: ["book_id": .string(book.id.uuidString)])
            library.share(book)
        }
        if library.pinned.contains(book.id) {
            Button("Remove Offline Download", systemImage: "icloud") {
                AppLog.debug("Remove Offline Download selected", category: "navigation", metadata: ["book_id": .string(book.id.uuidString)])
                library.removeOffline(book)
            }
        } else {
            Button("Keep Offline", systemImage: "arrow.down.circle") {
                AppLog.debug("Keep Offline selected", category: "navigation", metadata: ["book_id": .string(book.id.uuidString)])
                library.keepOffline(book)
            }
        }
    }
}
