import SwiftUI

struct MiniPlayerView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 12) {
            Button {
                library.showingPlayer = true
            } label: {
                HStack(spacing: 12) {
                    if let book = library.player.book { BookCoverView(book: book).frame(width: 40, height: 52) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(library.player.book?.manifest.title ?? "").font(.subheadline.bold()).lineLimit(1)
                        Text(library.player.loading ? String(localized: "Downloading audio…") : library.player.chapterTitle)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("mini-player-open")
            Button(library.player.playing ? "Pause" : "Play", systemImage: library.player.playing ? "pause.fill" : "play.fill", action: library.player.toggle)
                .labelStyle(.iconOnly).font(.title2).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("mini-player-toggle")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 660)
    }
}
