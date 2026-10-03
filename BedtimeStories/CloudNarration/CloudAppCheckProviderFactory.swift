import FirebaseAppCheck
import FirebaseCore
import Foundation

final class CloudAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        // Simulator tests use injected services; release builds never bypass attestation.
        let provider = AppAttestProvider(app: app)
        let created = provider != nil
        Task { @MainActor in
            if created {
                AppLog.trace("Firebase attestation provider created", category: "cloud_narration", metadata: ["provider": .string("app_attest")])
            } else {
                AppLog.error("Firebase attestation provider creation failed", category: "cloud_narration", metadata: ["provider": .string("app_attest")])
            }
        }
        return provider
    }
}
