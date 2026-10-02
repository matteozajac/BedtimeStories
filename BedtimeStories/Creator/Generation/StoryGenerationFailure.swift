import Foundation

enum StoryGenerationFailure: Error, LocalizedError {
    case emptyDescription, descriptionTooLong, invalidResponse, unavailable(String), unsupportedLanguage
    case contextTooLong, refused, busy, cloudNetwork, cloudQuota, cloudUnavailable, generationFailed, saveFailed
    case invalidDuration, localDurationTooLong, durationMismatch

    var errorDescription: String? {
        switch self {
        case .emptyDescription: String(localized: "Describe the story you would like to create.")
        case .descriptionTooLong: String(localized: "Keep your description within 600 characters so there is room for the story.")
        case .invalidResponse: String(localized: "The story was incomplete. Try a simpler description or a shorter reading time.")
        case .invalidDuration: String(localized: "Choose 1–30 minutes and a reading pace of 80–180 words per minute.")
        case .localDurationTooLong: String(localized: "This reading time is too long for the on-device model to create a complete book at once. Choose Private Cloud Compute or reduce the duration or reading pace.")
        case .durationMismatch: String(localized: "The story did not match your reading time. Try again, or choose a shorter duration.")
        case .unavailable(let reason): reason
        case .unsupportedLanguage: String(localized: "This model does not support the selected language. Choose another language or write the story yourself.")
        case .contextTooLong: String(localized: "There is too much detail for this model. Shorten your description and try again.")
        case .refused: String(localized: "The model could not create this story. Try a gentle, child-friendly idea.")
        case .busy: String(localized: "The model is busy. Wait a moment and try again.")
        case .cloudNetwork: String(localized: "Private Cloud Compute could not connect. Check your connection or choose On This Device.")
        case .cloudQuota: String(localized: "Your Private Cloud Compute limit has been reached. Try again later or choose On This Device.")
        case .cloudUnavailable: String(localized: "Private Cloud Compute is unavailable right now. Try again later or choose On This Device.")
        case .generationFailed: String(localized: "The story could not be completed. Try again with a shorter reading time or a simpler idea.")
        case .saveFailed: String(localized: "The generated draft could not be saved. Free some space on this device and try again.")
        }
    }
}
