#if MZ_LOCAL
import AuthenticationServices
import Foundation
import Observation

/// Local builds never load Firebase or grant access using simulated account state.
@Observable @MainActor
final class CloudNarrationModel {
    private(set) var isConfigured = false
    private(set) var isEnabled = false
    private(set) var userID: String?
    private(set) var isWorking = false
    var message: String?
    private(set) var voices: [VoiceProfile] = []
    private(set) var jobs: [NarrationJob] = []

    init(configureFirebase: Bool = true) {
        AppLog.trace("Cloud narration configuration skipped", category: "cloud_narration", metadata: ["reason": .string("local_services")])
    }

    func generateStory(_ request: StoryGenerationRequest) async throws -> GeneratedStoryBook { throw StoryGenerationFailure.geminiUnavailable }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) { message = CloudNarrationFailure.unavailable.localizedDescription }
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) { message = CloudNarrationFailure.unavailable.localizedDescription }
    func signOut() {}
    func beginEnrollment(name: String, language: String, retentionAccepted: Bool) async throws -> VoiceEnrollment { throw CloudNarrationFailure.unavailable }
    func uploadEnrollment(enrollment: VoiceEnrollment, referenceURL: URL, consentURL: URL) async throws -> String { throw CloudNarrationFailure.unavailable }
    func approveVoice(profileID: String) async throws { throw CloudNarrationFailure.unavailable }
    func startVoicePreview(profileID: String) async throws -> String { throw CloudNarrationFailure.unavailable }
    func startNarration(draft: BookDraft, voiceID: String, styles: [UUID: [NarrationStyle]],
                        defaultStyle: NarrationStyle, preview: Bool) async throws -> String { throw CloudNarrationFailure.unavailable }
    func snapshotHash(draft: BookDraft, styles: [UUID: [NarrationStyle]], defaultStyle: NarrationStyle) -> String {
        do { return try NarrationSnapshot(draft: draft, styles: styles, defaultStyle: defaultStyle).hash }
        catch {
            AppLog.error("Narration snapshot hashing failed", error: error, category: "cloud_narration")
            return ""
        }
    }
    func cancel(jobID: String) async throws { throw CloudNarrationFailure.unavailable }
    func deleteVoice(profileID: String) async throws { throw CloudNarrationFailure.unavailable }
    func deleteAccount() async throws { throw CloudNarrationFailure.unavailable }
    func download(job: NarrationJob) async throws -> [UUID: URL] { throw CloudNarrationFailure.unavailable }
}
#endif
