import Foundation
import MZAppFoundation
#if !MZ_LOCAL && !targetEnvironment(simulator)
@preconcurrency import FirebaseCore
#endif

/// Inspects the app-owned Cloud Narration SDK without initializing it or sending events.
@MainActor enum AppFoundationDiagnostics {
    static func make(bundle: Bundle = .main) -> FoundationDiagnostics {
        let inventory = FoundationDiagnostics(bundle: bundle)
        #if !MZ_LOCAL && !targetEnvironment(simulator)
        let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist")
        return inventory.replacing(.firebase) { context in
            let file = FirebaseConfigurationInspection.inspect(
                bundleIdentifier: context.configuration.bundleIdentifier,
                path: path
            )
            // Cloud Narration starts after the services composition. Read its current state.
            let app = FirebaseApp.app()
            let projectID = file.details.first { $0.id == "PROJECT_ID" }?.value
            let appID = file.details.first { $0.id == "GOOGLE_APP_ID" }?.value
            let supplied = projectID == nil && appID == nil ? nil : ProviderProjectIdentity(
                projectID: projectID, appID: appID
            )
            let running = app.map {
                ProviderProjectIdentity(projectID: $0.options.projectID, appID: $0.options.googleAppID)
            }
            return ProviderSnapshot(
                provider: .firebase,
                sdkVersion: FirebaseVersion(),
                versionSource: "FirebaseCore runtime",
                configuration: file.state,
                runtime: app != nil ? .initialized : .notInitialized,
                delivery: .notApplicable,
                details: file.details,
                explanation: file.explanation + " Firebase is owned by Cloud Narration. Foundation Analytics is not integrated.",
                identityAudit: .init(
                    supplied: supplied,
                    running: running,
                    ownership: app == nil ? .notInitialized : .external
                )
            )
        }
        #else
        return inventory
        #endif
    }
}
