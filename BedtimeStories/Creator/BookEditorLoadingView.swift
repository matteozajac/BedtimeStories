import SwiftUI

/// Stands in for the book editor while its editing draft is being prepared.
struct BookEditorLoadingView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if let failure = library.openingFailure {
                ContentUnavailableView {
                    Label("Unable to open book", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again") { library.retryEditBook() }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(Theme.accent)
                    Text("Opening book for editing…").font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { StoryBackground() }
        .navigationTitle("Edit Book").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { library.closeEditor() }.accessibilityIdentifier("close-book-editor")
            }
        }
    }
}
