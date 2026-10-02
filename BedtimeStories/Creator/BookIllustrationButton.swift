import ImagePlayground
import SwiftUI

struct BookIllustrationButton: View {
    @Environment(\.supportsImagePlayground) private var supported
    let editor: BookEditorModel
    var chapterID: UUID?
    @State private var preparing = false
    @State private var preparationID: UUID?
    @State private var presented = false
    @State private var concepts: [ImagePlaygroundConcept] = []
    @State private var sourceImage: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(chapterID == nil ? "Generate Cover Picture" : "Generate Chapter Picture", systemImage: "wand.and.stars") { preparationID = UUID() }
                .disabled(!supported || preparing || editor.working)
                .accessibilityIdentifier(chapterID == nil ? "generate-cover-picture" : "generate-chapter-picture")
            if preparing { ProgressView("Preparing picture idea…") }
            Text(supported ? "Image Playground starts with this story and a shared illustration style. Review the picture before keeping it." : "Image Playground is unavailable on this device. You can still add your own photos.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .task(id: preparationID) {
            guard preparationID != nil else { return }
            preparing = true
            defer { preparing = false }
            let snapshot = editor.draft
            let scene = try? await IllustrationPromptBuilder.prepare(snapshot, chapterID: chapterID)
            guard !Task.isCancelled else { return }
            let current = editor.draft
            concepts = [.text(IllustrationPromptBuilder.style)]
            let shared = IllustrationPromptBuilder.sharedGuide(current)
            if !shared.isEmpty { concepts.append(.text(shared)) }
            if current.hasSameContent(as: snapshot), let scene { concepts.append(.text(scene)) }
            else { concepts.append(.extracted(from: String(IllustrationPromptBuilder.context(current, chapterID: chapterID).prefix(6_000)), title: String(current.title.prefix(100)))) }
            sourceImage = nil
            // The cover provides a visual reference for the rest of the book.
            let path = chapterID.flatMap { id in current.chapters.first(where: { $0.id == id })?.image } ?? current.cover
            if let path, let url = try? await editor.store.mediaURL(path, draftID: current.id),
               let data = try? await editor.store.imageData(at: url), let image = await ArtworkDecoder.thumbnail(data) {
                sourceImage = Image(uiImage: UIImage(cgImage: image))
            }
            if let cover = current.cover, chapterID != nil, cover != path,
               let url = try? await editor.store.mediaURL(cover, draftID: current.id),
               let data = try? await editor.store.imageData(at: url), let image = await ArtworkDecoder.thumbnail(data) {
                concepts.append(.image(image))
            }
            guard !Task.isCancelled else { return }
            presented = true
        }
        .imagePlaygroundSheet(isPresented: $presented, concepts: concepts, sourceImage: sourceImage) { url in
            Task {
                do {
                    let data = try await editor.store.imageData(at: url)
                    await editor.setImage(data, chapterID: chapterID)
                } catch { editor.message = String(localized: "The generated picture could not be saved. Try creating it again.") }
            }
        }
        .imagePlaygroundGenerationStyle(.illustration, in: [.illustration])
    }
}
