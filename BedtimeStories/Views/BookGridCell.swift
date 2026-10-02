import SwiftUI

struct BookGridCell: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var selected = false

    var body: some View {
        let nowPlaying = library.player.book?.id == book.id
        VStack(alignment: .leading, spacing: 12) {
            BookCoverView(book: book)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if nowPlaying {
                        Image(systemName: "waveform")
                            .font(.caption.weight(.bold))
                            .symbolEffect(.variableColor.iterative, isActive: library.player.playing)
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent, in: .circle)
                            .padding(8)
                            .accessibilityLabel("Now Playing")
                    }
                }
                .overlay {
                    if selected {
                        BookShape(radius: 12).strokeBorder(Theme.accent, lineWidth: 3).padding(-6)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(book.manifest.title).storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink).lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let author = book.manifest.author { Text(author).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            HStack(spacing: 6) {
                if book.manifest.hasAudio { FormatBadge(systemName: "headphones").accessibilityLabel("Audiobook") }
                if book.manifest.hasReading { FormatBadge(systemName: "book.fill").accessibilityLabel("Readable book") }
                Spacer(minLength: 0)
                if library.pinned.contains(book.id) {
                    Image(systemName: "arrow.down.circle.fill").font(.subheadline).foregroundStyle(.tertiary).accessibilityLabel("Kept offline")
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A small round badge showing whether a book can be heard or read.
struct FormatBadge: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 28, height: 28)
            .background(Theme.accentSoft, in: .circle)
    }
}
