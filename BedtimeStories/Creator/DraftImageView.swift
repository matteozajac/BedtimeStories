import SwiftUI

struct DraftImageView: View {
    let path: String?
    let draftID: UUID
    let store: BookDraftStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity) }
        }
        .accessibilityLabel("Book artwork")
        .task(id: path) {
            image = nil
            guard let path else { return }
            do {
                let url = try await store.mediaURL(path, draftID: draftID)
                let data = try await store.imageData(at: url)
                let thumbnail = await ArtworkDecoder.thumbnail(data)
                guard !Task.isCancelled else { return }
                image = thumbnail.map { UIImage(cgImage: $0) }
            } catch { }
        }
    }
}
