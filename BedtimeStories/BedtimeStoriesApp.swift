import SwiftUI

@main
struct BedtimeStoriesApp: App {
    @State private var library = LibraryModel()
    @State private var cloud: CloudNarrationModel

    init() {
        Theme.applyNavigationBarAppearance()
        _cloud = State(initialValue: CloudNarrationModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(cloud)
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
    }
}
