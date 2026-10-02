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
            VStack(spacing: 0) {
                if loading { ProgressView("Opening chapter…").frame(maxWidth: .infinity).padding(.vertical, 48) }
                if let chapter {
                    VStack(spacing: 14) {
                        if chapters.count > 1 { Eyebrow(Text("Chapter \(index + 1) of \(chapters.count)")) }
                        Text(chapter.title ?? book.manifest.title)
                            .storyFont(.largeTitle, weight: .bold).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        StoryOrnament()
                    }
                    .frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 32)
                    if let illustration {
                        Image(uiImage: illustration).resizable().scaledToFit()
                            .clipShape(.rect(cornerRadius: 20))
                            .shadow(color: Theme.shadow, radius: 18, y: 8)
                            .padding(.bottom, 32)
                            .accessibilityLabel("Chapter illustration")
                    }
                    if let content { StoryTextView(content: content, size: size, markdown: chapter.text?.hasSuffix(".md") == true, chapterTitle: chapter.title) }
                    if let error {
                        VStack(spacing: 12) {
                            Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Try Again") { Task { await loadChapter() } }.buttonStyle(.storySoft)
                        }
                        .frame(maxWidth: .infinity).storyCard()
                    }
                    if !loading { chapterEnd }
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 40)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .id(chapter?.id)
        .background { StoryBackground(style: .reading) }
        .navigationTitle(book.manifest.title).navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Text Size") {
                        ControlGroup {
                            Button("Smaller Text", systemImage: "textformat.size.smaller") { size = max(16, size - 2) }
                            Button("Larger Text", systemImage: "textformat.size.larger") { size = min(36, size + 2) }
                        }
                    }
                    Picker("Appearance", selection: $appearance) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                        Label("Light", systemImage: "sun.max").tag("light")
                        Label("Dark", systemImage: "moon").tag("dark")
                    }
                    Section("Chapters") {
                        ForEach(chapters) { item in
                            Button { chapterID = item.id } label: {
                                if item.id == chapter?.id { Label(item.title ?? book.manifest.title, systemImage: "checkmark") }
                                else { Text(item.title ?? book.manifest.title) }
                            }
                        }
                    }
                } label: { Image(systemName: "textformat").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Reading options")
            }
        }
        .task(id: chapterID) { await loadChapter() }
        .onAppear { if chapterID == nil { chapterID = startingChapter ?? library.progress.readingChapter(book.id) ?? chapters.first?.id } }
    }

    @ViewBuilder private var chapterEnd: some View {
        VStack(spacing: 20) {
            if index + 1 < chapters.count {
                let next = chapters[index + 1]
                Button { chapterID = next.id } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow("Next Chapter")
                            Text(next.title ?? book.manifest.title).storyFont(.title3, weight: .semibold).foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .font(.title3.weight(.bold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 52, height: 52).background(Theme.accent, in: .circle)
                            .accessibilityHidden(true)
                    }
                    .storyCard(padding: 20)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .combine)
            } else {
                VStack(spacing: 8) {
                    MoonIllustration(size: 52)
                    Text("The End").storyFont(.title, weight: .bold).foregroundStyle(Theme.ink)
                    Text("Sweet dreams.").storyFont(.title3).italic().foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            if index > 0 {
                Button("Previous", systemImage: "chevron.left") { chapterID = chapters[index - 1].id }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .padding(.top, 48)
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
