import SwiftUI
import MZAppFoundation

struct StoryTextBlockView: View {
    let block: StoryTextBlock
    let size: Double
    let markdown: Bool
    private var renderedContent: (text: AttributedString, failure: ErrorSnapshot?) {
        guard markdown else { return (AttributedString(block.text), nil) }
        do {
            return (try AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)), nil)
        } catch {
            return (AttributedString(block.text), ErrorSnapshot(error))
        }
    }
    var body: some View {
        let rendered = renderedContent
        let content = rendered.text
        return Group {
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
        .onAppear {
            if let error = rendered.failure {
                AppLog.logger.log(LogEntry("Story Markdown formatting failed; displaying plain text", level: .warning, category: "reader", metadata: [
                    "text_character_count": .integer(block.text.count), "recovery": .string("plain_text")
                ], error: error))
            }
        }
    }
}
