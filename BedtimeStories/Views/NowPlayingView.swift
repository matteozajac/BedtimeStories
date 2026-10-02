import SwiftUI

struct NowPlayingView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrub = 0.0
    @State private var scrubbing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let book = library.player.book {
                        BookCoverView(book: book).aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 280 : 230)
                            .scaleEffect(library.player.playing || reduceMotion ? 1 : 0.92)
                            .animation(.spring(duration: 0.6, bounce: 0.3), value: library.player.playing)
                            .padding(.top, 8)
                        VStack(spacing: 8) {
                            Text(book.manifest.title).storyFont(.title, weight: .bold).foregroundStyle(Theme.moonlight).multilineTextAlignment(.center)
                            Text(library.player.chapterTitle).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if library.player.loading { ProgressView("Downloading audio…") }
                        if let error = library.player.error { Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        VStack(spacing: 6) {
                            Slider(value: Binding(get: { scrubbing ? scrub : library.player.elapsed }, set: { scrub = $0 }), in: 0...max(1, library.player.duration)) { editing in
                                scrubbing = editing
                                if !editing { library.player.seek(scrub) }
                            }
                            .tint(Theme.moonlight)
                            .disabled(library.player.loading || library.player.duration == 0).accessibilityLabel("Playback position")
                            HStack {
                                Text(Duration.seconds(library.player.elapsed).formatted(.time(pattern: .minuteSecond)))
                                Spacer()
                                Text("−" + Duration.seconds(max(0, library.player.duration - library.player.elapsed)).formatted(.time(pattern: .minuteSecond)))
                            }.font(.footnote.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        transport
                        PlayerOptionsView()
                        if !book.manifest.orderedChapters.isEmpty { chapters(of: book) }
                    } else { ContentUnavailableView("Nothing playing", systemImage: "headphones") }
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
                .frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .background { PlayerBackdrop(book: library.player.book) }
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
        .preferredColorScheme(.dark)
    }

    private var transport: some View {
        HStack(spacing: 30) {
            Button("Back 15 seconds", systemImage: "gobackward.15") { library.player.skip(-15) }
                .font(.title2.weight(.semibold)).foregroundStyle(Theme.moonlight)
                .frame(width: 64, height: 64).glassEffect(.regular.interactive(), in: .circle)
            Button(library.player.playing ? "Pause" : "Play", systemImage: library.player.playing ? "pause.fill" : "play.fill", action: library.player.toggle)
                .font(.system(size: 34, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Color(hex: 0x1F1830))
                .offset(x: library.player.playing ? 0 : 2)
                .frame(width: 88, height: 88)
                .background(Theme.moonlight, in: .circle)
                .shadow(color: Theme.moonlight.opacity(0.35), radius: 24)
                .accessibilityIdentifier("player-toggle")
            Button("Forward 15 seconds", systemImage: "goforward.15") { library.player.skip(15) }
                .font(.title2.weight(.semibold)).foregroundStyle(Theme.moonlight)
                .frame(width: 64, height: 64).glassEffect(.regular.interactive(), in: .circle)
        }
        .labelStyle(.iconOnly).buttonStyle(.pressable)
        .disabled(library.player.loading)
    }

    private func chapters(of book: LibraryBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Chapters").storyFont(.title3, weight: .bold).foregroundStyle(Theme.moonlight)
                .padding(.horizontal, 6).padding(.bottom, 6)
            ForEach(Array(book.manifest.orderedChapters.enumerated()), id: \.element.id) { index, chapter in
                let current = library.player.currentChapterID == chapter.id
                Button { library.player.selectChapter(chapter) } label: {
                    HStack(spacing: 14) {
                        ChapterNumber(number: index + 1, highlighted: current)
                        Text(chapter.title ?? String(localized: "Chapter \(index + 1)"))
                            .storyFont(.body).foregroundStyle(Theme.moonlight).opacity(current ? 1 : 0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if current {
                            Image(systemName: "waveform").foregroundStyle(Theme.accent)
                                .symbolEffect(.variableColor.iterative, isActive: library.player.playing)
                                .accessibilityLabel("Now Playing")
                        }
                    }
                    .frame(minHeight: 52).contentShape(.rect)
                }
                .buttonStyle(.plain).disabled(chapter.audio == nil && chapter.startTime == nil)
            }
        }
        .storyCard(padding: 14)
    }
}

/// A dim night sky tinted by the book, so the player stays calm in a dark room.
private struct PlayerBackdrop: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook?
    @State private var artwork: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.nightTop, Theme.nightBottom], startPoint: .top, endPoint: .bottom)
            if let book {
                RadialGradient(colors: [StoryPalette(for: book.id).skyTop.opacity(0.5), .clear],
                               center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 460)
            }
            if let artwork {
                Image(uiImage: artwork).resizable().scaledToFill().blur(radius: 70).opacity(0.35)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            Starfield(color: Theme.moonlight, intensity: 0.55, twinkles: true)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: "\(book?.id.uuidString ?? "")-\(book?.manifest.cover ?? "")") {
            guard let book else { artwork = nil; return }
            let image = await library.image(book.manifest.cover, book: book)
            withAnimation(.easeOut(duration: 0.4)) { artwork = image }
        }
    }
}
