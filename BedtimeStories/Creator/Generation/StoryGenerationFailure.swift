import Foundation

enum StoryGenerationFailure: Error, LocalizedError {
    case emptyDescription, descriptionTooLong, invalidResponse, unavailable(String), unsupportedLanguage
    case contextTooLong, refused, busy, cloudNetwork, cloudQuota, cloudUnavailable, generationFailed, saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyDescription: String(localized: "Describe the story you would like to create.")
        case .descriptionTooLong: String(localized: "Keep your description within 600 characters so there is room for the story.")
        case .invalidResponse: String(localized: "The story was incomplete. Try a simpler description or fewer chapters.")
        case .unavailable(let reason): reason
        case .unsupportedLanguage: String(localized: "This model does not support the selected language. Choose another language or write the story yourself.")
        case .contextTooLong: String(localized: "There is too much detail for this model. Shorten your description and try again.")
        case .refused: String(localized: "The model could not create this story. Try a gentle, child-friendly idea.")
        case .busy: String(localized: "The model is busy. Wait a moment and try again.")
        case .cloudNetwork: String(localized: "Private Cloud Compute could not connect. Check your connection or choose On This Device.")
        case .cloudQuota: String(localized: "Your Private Cloud Compute limit has been reached. Try again later or choose On This Device.")
        case .cloudUnavailable: String(localized: "Private Cloud Compute is unavailable right now. Try again later or choose On This Device.")
        case .generationFailed: String(localized: "The story could not be completed. Try again with fewer chapters or a simpler idea.")
        case .saveFailed: String(localized: "The generated draft could not be saved. Free some space on this device and try again.")
        }
    }
}
