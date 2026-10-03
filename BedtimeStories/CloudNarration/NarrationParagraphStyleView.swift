import SwiftUI

struct NarrationParagraphStyleView: View {
    let chapter: DraftChapter
    let defaultStyle: NarrationStyle
    @Binding var overrides: [Int: NarrationStyle]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chapter.title.isEmpty ? String(localized: "Untitled Chapter") : chapter.title)
                        .storyFont(.title2, weight: .bold).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Label(String(localized: "Book style: \(defaultStyle.title)"), systemImage: defaultStyle.symbolName)
                        .labelStyle(CompactLabelStyle())
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            Section {
                ForEach(Array(Self.paragraphs(chapter).enumerated()), id: \.offset) { index, paragraph in
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(Text("Paragraph \(index + 1)"), color: .secondary)
                        Text(paragraph).storyFont(.body).lineSpacing(4).foregroundStyle(Theme.ink)
                        Menu {
                            Button("Use Book Style") { overrides[index] = nil }
                            Divider()
                            ForEach(NarrationStyle.allCases, id: \.rawValue) { style in
                                Button(style.title, systemImage: style.symbolName) { overrides[index] = style }
                            }
                        } label: {
                            NarrationStyleChip(title: overrides[index]?.title ?? String(localized: "Book style: \(defaultStyle.title)"),
                                               style: overrides[index] ?? defaultStyle, selected: overrides[index] != nil)
                        }
                        .accessibilityLabel(String(localized: "Style for paragraph \(index + 1)"))
                        .accessibilityValue(overrides[index]?.title ?? defaultStyle.title)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .storyFormStyle()
        .navigationTitle("Paragraph Styles").navigationBarTitleDisplayMode(.inline)
    }

    static func paragraphs(_ chapter: DraftChapter) -> [String] {
        NarrationSnapshot.paragraphs(in: chapter)
    }
}
