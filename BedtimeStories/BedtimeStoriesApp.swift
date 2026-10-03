import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

@main
struct BedtimeStoriesApp: App {
    private let services = MZBootstrap.services
    @State private var library: LibraryModel
    @State private var cloud: CloudNarrationModel

    init() {
        AppLog.logger = MZBootstrap.services.logger
        // Hosted tests exercise console presentation without ReplayKit's consent UI.
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            MZBootstrap.reporting.recordsRecentActivity = false
        }
        Theme.applyNavigationBarAppearance()
        _library = State(initialValue: LibraryModel())
        _cloud = State(initialValue: CloudNarrationModel())
        AppLog.info("Application started", category: "app", metadata: [
            "version": .string(services.configuration.version),
            "build": .string(services.configuration.build),
            "environment": .string(services.configuration.environment.rawValue)
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(cloud)
                .environment(services.developerOptions)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .appDeveloperTools(services.developerOptions, reporting: MZBootstrap.reporting)
        }
    }
}
