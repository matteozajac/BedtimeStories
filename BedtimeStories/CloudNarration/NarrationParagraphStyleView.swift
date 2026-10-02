import SwiftUI

struct NarrationParagraphStyleView: View {
    let chapter: DraftChapter
    let defaultStyle: NarrationStyle
    @Binding var overrides: [Int: NarrationStyle]

    var body: some View {
        List {
            ForEach(Array(Self.paragraphs(chapter).enumerated()), id: \.offset) { index, paragraph in
                VStack(alignment: .leading, spacing: 12) {
                    Text(paragraph).font(.body)
                    Menu {
                        Button("Use Book Style") { overrides[index] = nil }
                        Divider()
                        ForEach(NarrationStyle.allCases, id: \.rawValue) { style in
                            Button(style.title) { overrides[index] = style }
                        }
                    } label: {
                        Label(overrides[index]?.title ?? String(localized: "Book style: \(defaultStyle.title)"), systemImage: "waveform")
                    }
                    .accessibilityLabel(String(localized: "Style for paragraph \(index + 1)"))
                    .accessibilityValue(overrides[index]?.title ?? defaultStyle.title)
                }.padding(.vertical, 6)
            }
        }
        .navigationTitle("Paragraph Styles").navigationBarTitleDisplayMode(.inline)
    }

    static func paragraphs(_ chapter: DraftChapter) -> [String] {
        NarrationSnapshot.paragraphs(in: chapter)
    }
}
