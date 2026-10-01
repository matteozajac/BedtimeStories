import SwiftUI

struct BookActionsMenu: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var body: some View {
        Button("Share Book", systemImage: "square.and.arrow.up") { library.share(book) }
        if library.pinned.contains(book.id) {
            Button("Remove Offline Download", systemImage: "icloud") { library.removeOffline(book) }
        } else {
            Button("Keep Offline", systemImage: "arrow.down.circle") { library.keepOffline(book) }
        }
    }
}
