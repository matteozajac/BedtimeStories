import SwiftUI

struct FolderWelcomeView: View {
    @Environment(LibraryModel.self) private var library
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "moon.stars").font(.system(size: 72)).foregroundStyle(.indigo).accessibilityHidden(true)
                Text("A little story.\nA peaceful night.").font(.largeTitle.bold()).fontDesign(.serif).multilineTextAlignment(.center)
                Text("Your family’s stories, together in one place. Choose an iCloud Drive folder to begin.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 18) {
                    Label("Create or choose a folder in iCloud Drive.", systemImage: "folder")
                    Label("Share the folder with your family in Files.", systemImage: "person.2")
                    Label("Add book folders with text, pictures, or audio.", systemImage: "books.vertical")
                }
                .foregroundStyle(.secondary)
                Button("Choose Library Folder", systemImage: "folder.badge.plus") { library.showingFolderPicker = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("choose-library-folder")
                Text("You can change the folder later in Settings. Sharing is managed in Files.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .navigationTitle("Always Near Stories").navigationBarTitleDisplayMode(.inline)
    }
}
