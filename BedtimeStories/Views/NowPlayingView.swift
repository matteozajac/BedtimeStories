import SwiftUI

struct NowPlayingView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var scrub = 0.0
    @State private var scrubbing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let book = library.player.book {
                        BookCoverView(book: book).aspectRatio(2.0 / 3.0, contentMode: .fit).frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 260 : 210)
                        VStack(spacing: 8) {
                            Text(book.manifest.title).font(.title.bold()).fontDesign(.serif).multilineTextAlignment(.center)
                            Text(library.player.chapterTitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if library.player.loading { ProgressView("Downloading audio…") }
                        if let error = library.player.error { Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        VStack(spacing: 8) {
                            Slider(value: Binding(get: { scrubbing ? scrub : library.player.elapsed }, set: { scrub = $0 }), in: 0...max(1, library.player.duration)) { editing in
                                scrubbing = editing
                                if !editing { library.player.seek(scrub) }
                            }.disabled(library.player.loading || library.player.duration == 0).accessibilityLabel("Playback position")
                            HStack {
                                Text(Duration.seconds(library.player.elapsed).formatted(.time(pattern: .minuteSecond)))
                                Spacer()
                                Text("−" + Duration.seconds(max(0, library.player.duration - library.player.elapsed)).formatted(.time(pattern: .minuteSecond)))
                            }.font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                        HStack(spacing: 36) {
                            Button("Back 15 seconds", systemImage: "gobackward.15") { library.player.skip(-15) }.font(.title).frame(minWidth: 44, minHeight: 44)
                            Button(library.player.playing ? "Pause" : "Play", systemImage: library.player.playing ? "pause.fill" : "play.fill", action: library.player.toggle)
                                .font(.system(size: 46)).frame(minWidth: 64, minHeight: 64).accessibilityIdentifier("player-toggle")
                            Button("Forward 15 seconds", systemImage: "goforward.15") { library.player.skip(15) }.font(.title).frame(minWidth: 44, minHeight: 44)
                        }.labelStyle(.iconOnly).disabled(library.player.loading)
                        PlayerOptionsView()
                        if !book.manifest.orderedChapters.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Chapters").font(.headline)
                                ForEach(Array(book.manifest.orderedChapters.enumerated()), id: \.element.id) { index, chapter in
                                    Button { library.player.selectChapter(chapter) } label: {
                                        HStack {
                                            Text(chapter.title ?? String(localized: "Chapter \(index + 1)"))
                                            Spacer()
                                            if library.player.currentChapterID == chapter.id { Image(systemName: "speaker.wave.2.fill") }
                                        }.frame(minHeight: 44)
                                    }.buttonStyle(.plain).disabled(chapter.audio == nil && chapter.startTime == nil)
                                }
                            }
                        }
                    } else { ContentUnavailableView("Nothing playing", systemImage: "headphones") }
                }.padding(28).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .sheet(isPresented: Binding(get: { library.shareURL != nil }, set: { if !$0 { library.shareURL = nil } })) {
                if let url = library.shareURL { ShareSheet(url: url) }
            }
            .navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close Player", systemImage: "chevron.down") { dismiss() }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("close-player")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let book = library.player.book { BookActionsMenu(book: book) }
                        Button("Stop Listening", systemImage: "stop") { library.player.stop(); dismiss() }
                    } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Player actions")
                }
            }
        }
    }
}
