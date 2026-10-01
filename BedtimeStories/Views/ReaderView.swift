import SwiftUI

struct ReaderView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var startingChapter: UUID?
    @AppStorage("readerSize") private var size = 21.0
    @AppStorage("readerAppearance") private var appearance = "system"
    @State private var chapterID: UUID?
    @State private var content: String?
    @State private var illustration: UIImage?
    @State private var error: String?
    @State private var loading = true
    private var chapters: [BookChapter] { book.manifest.orderedChapters.filter { $0.text != nil || $0.image != nil } }
    private var chapter: BookChapter? { chapters.first { $0.id == chapterID } ?? chapters.first }
    private var index: Int { chapters.firstIndex { $0.id == chapter?.id } ?? 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if loading { ProgressView("Opening chapter…").frame(maxWidth: .infinity) }
                if let chapter {
                    Text(chapter.title ?? book.manifest.title).font(.largeTitle.bold()).fontDesign(.serif)
                    if let illustration { Image(uiImage: illustration).resizable().scaledToFit().clipShape(.rect(cornerRadius: 12)).accessibilityLabel("Chapter illustration") }
                    if let content { StoryTextView(content: content, size: size, markdown: chapter.text?.hasSuffix(".md") == true, chapterTitle: chapter.title) }
                    if let error {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await loadChapter() } }
                    }
                    HStack {
                        Button("Previous", systemImage: "chevron.left") { chapterID = chapters[index - 1].id }.disabled(index == 0)
                        Spacer()
                        Button("Next", systemImage: "chevron.right") { chapterID = chapters[index + 1].id }.disabled(index + 1 >= chapters.count)
                    }.padding(.vertical).frame(minHeight: 44)
                }
            }.padding(28).frame(maxWidth: 740).frame(maxWidth: .infinity)
        }
        .id(chapter?.id)
        .navigationTitle(book.manifest.title).navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ControlGroup {
                        Button("Smaller Text", systemImage: "textformat.size.smaller") { size = max(16, size - 2) }
                        Button("Larger Text", systemImage: "textformat.size.larger") { size = min(36, size + 2) }
                    }
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    ForEach(chapters) { chapter in
                        Button(chapter.title ?? book.manifest.title) { chapterID = chapter.id }
                    }
                } label: { Image(systemName: "textformat").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Reading options")
            }
        }
        .task(id: chapterID) { await loadChapter() }
        .onAppear { if chapterID == nil { chapterID = startingChapter ?? library.progress.readingChapter(book.id) ?? chapters.first?.id } }
    }
    private func loadChapter() async {
        guard let chapter else { loading = false; return }
        content = nil; illustration = nil; error = nil; loading = true
        library.progress.saveReading(chapter.id, bookID: book.id)
        var loadedImage: UIImage?
        var loadedText: String?
        var failure: String?
        if let image = chapter.image {
            loadedImage = await library.image(image, book: book)
            if loadedImage == nil { failure = String(localized: "Chapter illustration is unavailable.") }
        }
        do {
            if let text = chapter.text { loadedText = try await library.text(text, book: book) }
        } catch is CancellationError { return }
        catch { failure = error.localizedDescription }
        guard !Task.isCancelled, self.chapter?.id == chapter.id else { return }
        illustration = loadedImage; content = loadedText; error = failure; loading = false

    }
}
