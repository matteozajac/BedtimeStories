import Foundation

public struct StoryTextBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case paragraph, heading(Int), list(String) }
    public var kind: Kind
    public var text: String

    public static func parse(_ text: String, markdown: Bool, omittingTitle title: String? = nil) -> [StoryTextBlock] {
        if !markdown { return text.components(separatedBy: "\n\n").filter { !$0.isEmpty }.map { Self(kind: .paragraph, text: $0) } }
        var blocks: [StoryTextBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(Self(kind: .paragraph, text: paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            let heading = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(heading), line.dropFirst(heading).hasPrefix(" ") {
                flush()
                let label = String(line.dropFirst(heading + 1))
                if blocks.isEmpty && label == title { continue }
                blocks.append(Self(kind: .heading(heading), text: label))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush(); blocks.append(Self(kind: .list("•"), text: String(line.dropFirst(2))))
            } else if let range = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flush(); blocks.append(Self(kind: .list(String(line[range]).trimmingCharacters(in: .whitespaces)), text: String(line[range.upperBound...])))
            } else { paragraph.append(line) }
        }
        flush()
        return blocks
    }
}
