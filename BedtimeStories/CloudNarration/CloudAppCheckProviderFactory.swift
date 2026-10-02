import FirebaseAppCheck
import FirebaseCore
import Foundation

final class CloudAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        // Simulator tests use injected services; release builds never bypass attestation.
        AppAttestProvider(app: app)
    }
}
