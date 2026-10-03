import CoreGraphics
import ImagePlayground
import MZAppFoundation
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

    private var diagnosticFields: [String: TelemetryValue] {
        var values: [String: TelemetryValue] = ["draft_id": .string(editor.draft.id.uuidString), "chapter_artwork": .bool(chapterID != nil)]
        if let chapterID { values["chapter_id"] = .string(chapterID.uuidString) }
        if let preparationID { values["operation_id"] = .string(preparationID.uuidString) }
        return values
    }

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
            AppLog.trace("Illustration preparation started", category: "creator", metadata: diagnosticFields)
            let snapshot = editor.draft
            let scene: String?
            do { scene = try await IllustrationPromptBuilder.prepare(snapshot, chapterID: chapterID) }
            catch is CancellationError {
                AppLog.trace("Illustration preparation cancelled", category: "creator", metadata: diagnosticFields)
                return
            }
            catch {
                AppLog.warning("Illustration scene generation failed; using story context", error: error, category: "creator", metadata: diagnosticFields)
                scene = nil
            }
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
            if let path, let image = await loadReference(path, from: current) {
                sourceImage = Image(uiImage: UIImage(cgImage: image))
            }
            if let cover = current.cover, chapterID != nil, cover != path,
               let image = await loadReference(cover, from: current) {
                concepts.append(.image(image))
            }
            guard !Task.isCancelled else { return }
            presented = true
            AppLog.debug("Illustration preparation completed", category: "creator", metadata: diagnosticFields.merging(["has_generated_scene": .bool(scene != nil), "has_reference": .bool(sourceImage != nil)]) { _, new in new })
        }
        .imagePlaygroundSheet(isPresented: $presented, concepts: concepts, sourceImage: sourceImage) { url in
            Task {
                do {
                    let data = try await editor.store.imageData(at: url)
                    await editor.setImage(data, chapterID: chapterID)
                } catch is CancellationError { AppLog.trace("Generated illustration loading cancelled", category: "creator", metadata: diagnosticFields) }
                catch {
                    AppLog.error("Generated illustration loading failed", error: error, category: "creator", metadata: diagnosticFields)
                    editor.message = String(localized: "The generated picture could not be saved. Try creating it again.")
                }
            }
        }
        .imagePlaygroundGenerationStyle(.illustration, in: [.illustration])
    }

    private func loadReference(_ path: String, from draft: BookDraft) async -> CGImage? {
        do {
            let url = try await editor.store.mediaURL(path, draftID: draft.id)
            let data = try await editor.store.imageData(at: url)
            let image = await ArtworkDecoder.thumbnail(data)
            guard !Task.isCancelled else { return nil }
            if image == nil { AppLog.warning("Illustration reference could not be decoded", category: "creator", metadata: diagnosticFields) }
            return image
        } catch is CancellationError { return nil }
        catch {
            AppLog.warning("Illustration reference unavailable", error: error, category: "creator", metadata: diagnosticFields)
            return nil
        }
    }
}
