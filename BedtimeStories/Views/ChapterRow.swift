import SwiftUI

struct ChapterRow: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    let chapter: BookChapter
    let number: Int

    var body: some View {
        let current = library.player.book?.id == book.id && library.player.currentChapterID == chapter.id
        let title = chapter.title ?? String(localized: "Chapter \(number)")
        HStack(spacing: 12) {
            if chapter.text != nil || chapter.image != nil {
                NavigationLink { ReaderView(book: book, startingChapter: chapter.id) } label: {
                    HStack(spacing: 14) {
                        ChapterNumber(number: number, highlighted: current)
                        Text(title).storyFont(.body).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain).frame(minHeight: 52)
            } else {
                HStack(spacing: 14) {
                    ChapterNumber(number: number, highlighted: current)
                    Text(title).storyFont(.body).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 52)
            }
            if chapter.audio != nil || (book.manifest.audio != nil && chapter.startTime != nil) {
                Button("Play chapter", systemImage: current && library.player.playing ? "waveform" : "play.fill") { library.listen(book, chapter: chapter) }
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.bold))
                    .symbolEffect(.variableColor.iterative, isActive: current && library.player.playing)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accentSoft, in: .circle)
                    .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A round chapter number that fills in while the chapter is playing.
struct ChapterNumber: View {
    let number: Int
    var highlighted = false
    var body: some View {
        Text(number, format: .number)
            .font(.subheadline.weight(.bold)).monospacedDigit()
            .foregroundStyle(highlighted ? Theme.onAccent : Theme.accent)
            .frame(width: 36, height: 36)
            .background(highlighted ? Theme.accent : Theme.accentSoft, in: .circle)
    }
}
