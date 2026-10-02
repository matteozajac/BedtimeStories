import SwiftUI

struct FolderWelcomeView: View {
    @Environment(LibraryModel.self) private var library
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "moon.stars").font(.system(size: 72)).foregroundStyle(.indigo).accessibilityHidden(true)
                Text("A little story.\nA peaceful night.").font(.largeTitle.bold()).fontDesign(.serif).multilineTextAlignment(.center)
                Text("Your library has a home. We’ll use Always Near Stories in iCloud Drive and create it if needed.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 18) {
                    Label("Your books sync between devices using the same Apple Account.", systemImage: "icloud")
                    Label("If iCloud Drive is off, books stay on this device until it is available.", systemImage: "iphone")
                    Label("Create complete stories, add pictures, and record your voice.", systemImage: "books.vertical")
                }.foregroundStyle(.secondary)
                Button("Continue", systemImage: "arrow.right") { Task { await library.acceptDefaultLibrary() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(library.preparingLibrary).accessibilityIdentifier("open-default-library")
                if library.preparingLibrary { ProgressView("Opening your library…") }
                Text("Continuing lets the app store your books in its iCloud folder when iCloud Drive is available. Manage family sharing in Files.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }.navigationTitle("Always Near Stories").navigationBarTitleDisplayMode(.inline)
    }
}
