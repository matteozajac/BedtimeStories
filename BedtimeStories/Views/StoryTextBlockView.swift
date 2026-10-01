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
                Text(content).font(.system(size: size + (level == 1 ? 8 : 4), weight: .bold, design: .serif)).accessibilityAddTraits(.isHeader)
            case .list(let marker):
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(marker).accessibilityHidden(true)
                    Text(content).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: size, design: .serif))
            case .paragraph:
                Text(content).font(.system(size: size, design: .serif))
            }
        }
        .lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}
