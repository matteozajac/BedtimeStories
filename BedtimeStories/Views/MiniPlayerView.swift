import SwiftUI

struct MiniPlayerView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let player = library.player
        HStack(spacing: 12) {
            Button {
                library.showingPlayer = true
            } label: {
                HStack(spacing: 12) {
                    if let book = player.book { BookCoverView(book: book, shadow: false).frame(width: 40, height: 56) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.book?.manifest.title ?? "").storyFont(.subheadline, weight: .semibold).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(player.loading ? String(localized: "Downloading audio…") : player.chapterTitle)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("mini-player-open")
            Button(player.playing ? "Pause" : "Play", systemImage: player.playing ? "pause.fill" : "play.fill", action: player.toggle)
                .labelStyle(.iconOnly)
                .font(.body.weight(.bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 42, height: 42)
                .background(Theme.accent, in: .circle)
                .padding(4)
                .overlay {
                    Circle().stroke(Theme.accent.opacity(0.18), lineWidth: 3)
                    Circle().trim(from: 0, to: player.duration > 0 ? min(1, player.elapsed / player.duration) : 0)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("mini-player-toggle")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 8)
        .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 660)
    }
}
