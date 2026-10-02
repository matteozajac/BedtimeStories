import SwiftUI

struct BookCoverView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var loadsArtwork = true
    var shadow = true
    @State private var artwork: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CoverArtwork(id: book.id, title: book.manifest.title)
                if let artwork {
                    Image(uiImage: artwork).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .bookStyle(width: geometry.size.width, shadow: shadow)
        }
        .accessibilityHidden(true)
        .task(id: "\(book.manifest.cover ?? "")-\(library.revision)") {
            guard loadsArtwork else { return }
            let image = await library.image(book.manifest.cover, book: book)
            withAnimation(.easeOut(duration: 0.25)) { artwork = image }
        }
    }
}

/// A soft wash of the book's cover behind its page, fading into the background.
struct BookBackdrop: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    let book: LibraryBook
    var height: CGFloat = 520
    @State private var artwork: UIImage?

    var body: some View {
        let palette = StoryPalette(for: book.id)
        ZStack(alignment: .top) {
            StoryBackground()
            Group {
                if let artwork {
                    Image(uiImage: artwork).resizable().scaledToFill().blur(radius: 50)
                        .opacity(colorScheme == .dark ? 0.4 : 0.32)
                } else {
                    LinearGradient(colors: [palette.skyTop.opacity(colorScheme == .dark ? 0.45 : 0.3), palette.skyBottom.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(height: height).frame(maxWidth: .infinity).clipped()
            .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: "\(book.manifest.cover ?? "")-\(library.revision)") {
            artwork = await library.image(book.manifest.cover, book: book)
        }
    }
}
