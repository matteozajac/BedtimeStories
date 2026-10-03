import SwiftUI

struct DraftImageView: View {
    let path: String?
    let draftID: UUID
    let store: BookDraftStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 16))
                    .frame(maxHeight: 240).frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .accessibilityLabel("Book artwork")
        .task(id: path) {
            image = nil
            image = await Self.load(path, draftID: draftID, store: store)
        }
    }

    static func load(_ path: String?, draftID: UUID, store: BookDraftStore) async -> UIImage? {
        guard let path else { return nil }
        do {
            let url = try await store.mediaURL(path, draftID: draftID)
            let data = try await store.imageData(at: url)
            let thumbnail = await ArtworkDecoder.thumbnail(data)
            guard !Task.isCancelled else { return nil }
            if thumbnail == nil { AppLog.warning("Draft artwork could not be decoded", category: "creator") }
            return thumbnail.map { UIImage(cgImage: $0) }
        } catch is CancellationError { return nil }
        catch {
            AppLog.warning("Draft artwork unavailable", error: error, category: "creator")
            return nil
        }
    }
}

/// A draft's cover as a small picture book, illustrated until a picture is added.
struct DraftCoverView: View {
    let draft: BookDraft
    let store: BookDraftStore
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CoverArtwork(id: draft.source?.bookID ?? draft.id, title: draft.title.isEmpty ? nil : draft.title)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .bookStyle(width: geometry.size.width)
        }
        .accessibilityHidden(true)
        .task(id: draft.cover) {
            image = await DraftImageView.load(draft.cover, draftID: draft.id, store: store)
        }
    }
}
