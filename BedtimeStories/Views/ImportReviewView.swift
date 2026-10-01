import SwiftUI

struct ImportReviewView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    private var replacing: Bool { library.books.contains { $0.id == book.id } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "books.vertical").font(.system(size: 48)).foregroundStyle(.indigo)
                Text(book.manifest.title).font(.title.bold()).fontDesign(.serif).multilineTextAlignment(.center)
                Text(replacing ? "This book is already in your library. Replacing it updates its text and media. Your progress stays on this device." : "Add this book to your selected library folder. Everyone sharing the folder will be able to open it.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(replacing ? "Replace Book" : "Add to Library") { library.commitImport(replacing: replacing) }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("confirm-import")
                Button("Cancel", action: library.cancelImport)
            }.padding(32).frame(maxWidth: 500).frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Import Book").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large])
    }
}
