import SwiftUI

@main
struct BedtimeStoriesApp: App {
    @State private var library = LibraryModel()

    init() { Theme.applyNavigationBarAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
    }
}
