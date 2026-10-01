import SwiftUI

struct BookCoverView: View {
    @Environment(LibraryModel.self) private var library
    let book: LibraryBook
    var path: String? = nil
    @State private var artwork: UIImage?
    private var assetPath: String? { path ?? book.manifest.cover }
    private var hue: Double { Double(book.id.uuidString.utf8.reduce(0) { $0 + Int($1) } % 100) / 100 }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let artwork {
                    Image(uiImage: artwork).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    LinearGradient(colors: [Color(hue: hue, saturation: 0.32, brightness: 0.42), Color(hue: hue, saturation: 0.45, brightness: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 14) {
                        Spacer(minLength: 0)
                        Image(systemName: "moon.stars").font(geometry.size.width > 100 ? .title : .caption).foregroundStyle(.white.opacity(0.8))
                        if geometry.size.width > 100 { Text(book.manifest.title).font(.title3.bold()).fontDesign(.serif)
                            .multilineTextAlignment(.center).foregroundStyle(.white).lineLimit(5).minimumScaleFactor(0.7) }
                        Spacer(minLength: 0)
                    }.padding()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.10)).frame(width: 5).padding(.vertical, 2) }
            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
        }
        .accessibilityHidden(true)
        .task(id: "\(assetPath ?? "")-\(library.revision)") { artwork = await library.image(assetPath, book: book) }
    }
}
