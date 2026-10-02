import Foundation

enum CloudNarrationFailure: LocalizedError {
    case unavailable, signInRequired, accountChanged, invalidResponse, invalidAudio, expired, staleVoice
    case limitReached, retryLater, permissionDenied, confirmWithApple, invalidRecording

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Voice generation is not available yet. You can still record and listen to your books.")
        case .signInRequired: String(localized: "Sign in with Apple to use your private voices.")
        case .accountChanged: String(localized: "Your account changed. Sign in again to continue.")
        case .invalidResponse: String(localized: "Your narration could not be opened. Try again.")
        case .invalidAudio: String(localized: "The audio could not be verified. Your previous narration is still saved.")
        case .expired: String(localized: "This narration has expired. Generate it again to continue.")
        case .staleVoice: String(localized: "Choose a voice from your account to continue.")
        case .limitReached: String(localized: "Your narration limit has been reached. Try again tomorrow.")
        case .retryLater: String(localized: "Voice generation could not connect. Your book is still saved. Try again shortly.")
        case .permissionDenied: String(localized: "This private voice or narration is unavailable for your account.")
        case .confirmWithApple: String(localized: "Confirm with Apple before deleting your voice or account.")
        case .invalidRecording: String(localized: "The recording could not be accepted. Record a clear sample and read the consent statement exactly.")
        }
    }
}
