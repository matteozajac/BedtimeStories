import SwiftUI

struct StoryTextView: View {
    let content: String
    let size: Double
    let markdown: Bool
    var chapterTitle: String?
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(StoryTextBlock.parse(content, markdown: markdown, omittingTitle: chapterTitle).enumerated()), id: \.offset) { _, block in
                StoryTextBlockView(block: block, size: size * scale, markdown: markdown)
            }
        }
    }
}
