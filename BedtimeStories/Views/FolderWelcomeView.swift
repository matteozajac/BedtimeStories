import SwiftUI

struct FolderWelcomeView: View {
    @Environment(LibraryModel.self) private var library
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                MoonIllustration(size: 104).padding(.top, 20)
                VStack(spacing: 14) {
                    Text("A little story.\nA peaceful night.")
                        .storyFont(.largeTitle, weight: .bold).foregroundStyle(Theme.moonlight)
                        .multilineTextAlignment(.center)
                    Text("Your library has a home. We’ll use Always Near Stories in iCloud Drive and create it if needed.")
                        .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    feature("Your books sync between devices using the same Apple Account.", systemImage: "icloud.fill")
                    feature("If iCloud Drive is off, books stay on this device until it is available.", systemImage: "iphone")
                    feature("Create complete stories, add pictures, and record your voice.", systemImage: "books.vertical.fill")
                }
                .storyCard()
                VStack(spacing: 16) {
                    Button { Task { await library.acceptDefaultLibrary() } } label: {
                        Label("Continue", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(.storyProminent(fullWidth: true))
                    .disabled(library.preparingLibrary).accessibilityIdentifier("open-default-library")
                    if library.preparingLibrary { ProgressView("Opening your library…") }
                    Text("Continuing lets the app store your books in its iCloud folder when iCloud Drive is available. Manage family sharing in Files.")
                        .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
            }
            .padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background { StoryBackground(style: .night) }
        .preferredColorScheme(.dark)
        .navigationTitle("Always Near Stories").navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private func feature(_ text: LocalizedStringKey, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(systemName: systemImage, color: Theme.glow, size: 36)
            Text(text).font(.body).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
