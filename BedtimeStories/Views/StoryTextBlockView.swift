import SwiftUI

struct StoryTextBlockView: View {
    let block: StoryTextBlock
    let size: Double
    let markdown: Bool
    private var content: AttributedString {
        markdown ? ((try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text)) : AttributedString(block.text)
    }
    var body: some View {
        Group {
            switch block.kind {
            case .heading(let level):
                Text(content).font(.system(size: size + (level == 1 ? 8 : 4), weight: .bold))
                    .lineSpacing(size * 0.15).padding(.top, size * 0.6).accessibilityAddTraits(.isHeader)
            case .list(let marker):
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(marker).foregroundStyle(Theme.glow).accessibilityHidden(true)
                    Text(content).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: size)).lineSpacing(size * 0.4)
            case .paragraph:
                Text(content).font(.system(size: size)).lineSpacing(size * 0.4)
            }
        }
        .fontDesign(.serif)
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}
