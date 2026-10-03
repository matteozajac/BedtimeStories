import SwiftUI

struct BookDetailView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    @State private var showsTitle = false

    var body: some View {
        let book = library.books.first(where: { $0.id == self.book.id }) ?? self.book
        let chapters = book.manifest.orderedChapters
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 22) {
                    BookCoverView(book: book).aspectRatio(2.0 / 3.0, contentMode: .fit).frame(maxWidth: 230)
                    VStack(spacing: 8) {
                        Text(book.manifest.title).storyFont(.largeTitle, weight: .bold).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                        if let author = book.manifest.author { Text(author).font(.title3).foregroundStyle(.secondary) }
                    }
                    actions(for: book)
                }
                if let description = book.manifest.description {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("About this story")
                        Text(description).storyFont(.body).foregroundStyle(Theme.ink.opacity(0.8)).lineSpacing(5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !book.manifest.hasAudio && !book.manifest.hasReading {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(Theme.glow).accessibilityHidden(true)
                        Text("A story waiting to happen").storyFont(.title3, weight: .semibold).foregroundStyle(Theme.ink)
                        Text("Text, pictures, and recordings can be added to this book’s folder whenever you’re ready.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).storyCard(padding: 28)
                }
                if !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Chapters").storyFont(.title2, weight: .bold).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(chapters.count, format: .number).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                                ChapterRow(book: book, chapter: chapter, number: index + 1)
                                if index + 1 < chapters.count { Divider().padding(.leading, 52) }
                            }
                        }
                        .storyCard(padding: 12, cornerRadius: 24)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 32)
            .frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { BookBackdrop(book: book) }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 380 } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { showsTitle = past }
        }
        .navigationTitle(book.manifest.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(book.manifest.title).font(.headline).lineLimit(1).opacity(showsTitle ? 1 : 0).accessibilityHidden(!showsTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu { BookActionsMenu(book: book) } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Book actions")
            }
        }
        .onAppear {
            AppLog.debug("Book details opened", category: "navigation", metadata: [
                "book_id": .string(book.id.uuidString), "chapter_count": .integer(chapters.count),
                "has_audio": .bool(book.manifest.hasAudio), "has_reading": .bool(book.manifest.hasReading)
            ])
        }
        .onDisappear {
            AppLog.trace("Book details left", category: "navigation", metadata: ["book_id": .string(book.id.uuidString)])
        }
    }

    @ViewBuilder private func actions(for book: LibraryBook) -> some View {
        HStack(spacing: 12) {
            if book.manifest.hasAudio {
                Button(library.progress.playback(book.id) == nil ? "Listen" : "Resume", systemImage: "play.fill") { library.listen(book) }
                    .buttonStyle(.storyProminent(fullWidth: true)).accessibilityIdentifier("listen-book")
            }
            if book.manifest.hasReading {
                if book.manifest.hasAudio {
                    NavigationLink { ReaderView(book: book) } label: { Label("Read", systemImage: "book.fill") }
                        .buttonStyle(.storySoft(fullWidth: true)).accessibilityIdentifier("read-book")
                } else {
                    NavigationLink { ReaderView(book: book) } label: { Label("Read", systemImage: "book.fill") }
                        .buttonStyle(.storyProminent(fullWidth: true)).accessibilityIdentifier("read-book")
                }
            }
        }
        .frame(maxWidth: 440)
    }
}
