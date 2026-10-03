import SwiftUI
import MZAppFoundation

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
                            Button("Try Again") {
                                AppLog.debug("Reader chapter reload requested", category: "reader", metadata: ["chapter_index": .integer(index)])
                                Task { await loadChapter() }
                            }.buttonStyle(.storySoft)
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
                            Button {
                                AppLog.debug("Reader chapter selected from menu", category: "reader", metadata: ["chapter_index": .integer(chapters.firstIndex { $0.id == item.id } ?? 0)])
                                chapterID = item.id
                            } label: {
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
        .onAppear {
            AppLog.debug("Book reader opened", category: "reader", metadata: ["readable_chapter_count": .integer(chapters.count), "has_requested_chapter": .bool(startingChapter != nil)])
            if chapterID == nil { chapterID = startingChapter ?? library.progress.readingChapter(book.id) ?? chapters.first?.id }
        }
        .onDisappear { AppLog.trace("Book reader closed", category: "reader", metadata: ["chapter_index": .integer(index), "chapter_loading": .bool(loading)]) }
        .onChange(of: size) { _, value in AppLog.debug("Reader text size changed", category: "reader", metadata: ["text_size": .double(value)]) }
        .onChange(of: appearance) { _, value in AppLog.debug("Reader appearance changed", category: "reader", metadata: ["appearance": .string(["system", "light", "dark"].contains(value) ? value : "unknown")]) }
    }

    @ViewBuilder private var chapterEnd: some View {
        VStack(spacing: 20) {
            if index + 1 < chapters.count {
                let next = chapters[index + 1]
                Button {
                    AppLog.debug("Reader next chapter requested", category: "reader", metadata: ["chapter_index": .integer(index + 1)])
                    chapterID = next.id
                } label: {
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
                Button("Previous", systemImage: "chevron.left") {
                    AppLog.debug("Reader previous chapter requested", category: "reader", metadata: ["chapter_index": .integer(index - 1)])
                    chapterID = chapters[index - 1].id
                }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .padding(.top, 48)
    }

    private func loadChapter() async {
        guard let chapter else {
            AppLog.warning("Reader has no chapter with text or an illustration", category: "reader", metadata: ["manifest_chapter_count": .integer(book.manifest.orderedChapters.count)])
            loading = false; return
        }
        let repository = library.repository
        let startedAt = ProcessInfo.processInfo.systemUptime
        let operationID = UUID().uuidString
        let fields: [String: TelemetryValue] = ["diagnostic_operation_id": .string(operationID), "chapter_index": .integer(index),
            "book_id": .string(book.id.uuidString), "chapter_id": .string(chapter.id.uuidString),
            "has_text_asset": .bool(chapter.text != nil), "has_image_asset": .bool(chapter.image != nil)]
        AppLog.trace("Reader chapter load started", category: "reader", metadata: fields)
        content = nil; illustration = nil; error = nil; loading = true
        library.progress.saveReading(chapter.id, bookID: book.id)
        var loadedImage: UIImage?
        var loadedText: String?
        var failure: String?
        if let image = chapter.image {
            AppLog.trace("Reader chapter illustration load started", category: "reader", metadata: fields)
            loadedImage = await library.image(image, book: book, operationID: operationID)
            await repository.flushDiagnosticLogs()
            AppLog.trace("Reader chapter illustration load completed", category: "reader", metadata: fields.merging(["available": .bool(loadedImage != nil)]) { _, new in new })
            if loadedImage == nil { failure = String(localized: "Chapter illustration is unavailable.") }
        }
        do {
            try Task.checkCancellation()
            if let text = chapter.text {
                AppLog.trace("Reader chapter text load started", category: "reader", metadata: fields)
                loadedText = try await library.text(text, book: book, operationID: operationID)
                await repository.flushDiagnosticLogs()
                AppLog.trace("Reader chapter text load completed", category: "reader", metadata: fields)
            }
        } catch is CancellationError {
            await repository.flushDiagnosticLogs()
            AppLog.trace("Reader chapter load cancelled", category: "reader", metadata: fields.merging(["duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)]) { _, new in new })
            return
        }
        catch {
            let snapshot = ErrorSnapshot(error)
            failure = error.localizedDescription
            await repository.flushDiagnosticLogs()
            AppLog.logger.log(LogEntry("Reader chapter text load failed", level: .error, category: "reader",
                metadata: fields.merging(["duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)]) { _, new in new },
                error: snapshot))
        }
        guard !Task.isCancelled, self.chapter?.id == chapter.id else {
            AppLog.trace("Reader chapter load result discarded after navigation", category: "reader", metadata: fields.merging(["cancelled": .bool(Task.isCancelled)]) { _, new in new })
            return
        }
        illustration = loadedImage; content = loadedText; error = failure; loading = false
        AppLog.debug("Reader chapter load completed", category: "reader", metadata: fields.merging([
            "has_text": .bool(loadedText != nil), "has_image": .bool(loadedImage != nil), "degraded": .bool(failure != nil),
            "duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        ]) { _, new in new })
    }
}
