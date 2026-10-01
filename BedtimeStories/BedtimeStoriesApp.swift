import SwiftUI

@main
struct BedtimeStoriesApp: App {
    @State private var library = LibraryModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(.indigo)
        }
    }
}
