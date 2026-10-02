import SwiftUI

struct ImportReviewView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    private var replacing: Bool { library.books.contains { $0.id == book.id } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CoverArtwork(id: book.id, title: book.manifest.title)
                        .frame(width: 96, height: 144)
                        .bookStyle(width: 96)
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text(book.manifest.title).storyFont(.title, weight: .bold).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                        if let author = book.manifest.author { Text(author).font(.title3).foregroundStyle(.secondary) }
                    }
                    Text(replacing ? "This book is already in your library. Replacing it updates its text and media. Your progress stays on this device." : "Add this book to your selected library folder. Everyone sharing the folder will be able to open it.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    VStack(spacing: 12) {
                        Button(replacing ? "Replace Book" : "Add to Library", systemImage: replacing ? "arrow.triangle.2.circlepath" : "plus") { library.commitImport(replacing: replacing) }
                            .buttonStyle(.storyProminent(fullWidth: true)).accessibilityIdentifier("confirm-import")
                        Button("Cancel", action: library.cancelImport)
                            .buttonStyle(.storySoft(fullWidth: true))
                    }
                }
                .padding(28).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
            .background { StoryBackground() }
            .navigationTitle("Import Book").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large])
    }
}
