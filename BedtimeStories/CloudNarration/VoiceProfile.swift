import Foundation
import NaturalLanguage

struct VoiceProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let language: String
    let status: String
    var createdAt: Double = 0
    var errorCode: String? = nil

    /// Only app-owned logical IDs leave the app. Provider names are resolved by the server.
    static let builtInVoices: [VoiceProfile] = [
        VoiceProfile(id: "builtin-en-luna", displayName: "Luna", language: "en-US", status: "ready"),
        VoiceProfile(id: "builtin-en-milo", displayName: "Milo", language: "en-US", status: "ready"),
        VoiceProfile(id: "builtin-en-robin", displayName: "Robin", language: "en-US", status: "ready"),
        VoiceProfile(id: "builtin-pl-luna", displayName: "Luna", language: "pl-PL", status: "ready"),
        VoiceProfile(id: "builtin-pl-milo", displayName: "Milo", language: "pl-PL", status: "ready"),
        VoiceProfile(id: "builtin-pl-robin", displayName: "Robin", language: "pl-PL", status: "ready"),
    ]

    var isBuiltIn: Bool { Self.builtInVoices.contains { $0.id == id } }

    var narrationDescription: String? {
        guard isBuiltIn else { return nil }
        switch id.split(separator: "-").last {
        case "luna": return String(localized: "Warm and comforting")
        case "milo": return String(localized: "Soft and soothing")
        case "robin": return String(localized: "Relaxed and friendly")
        default: return nil
        }
    }

    static func available(for language: StoryLanguage, personalVoices: [VoiceProfile]) -> [VoiceProfile] {
        let code = language == .polish ? "pl-PL" : "en-US"
        return personalVoices.filter { $0.status == "ready" && $0.language == code && !$0.isBuiltIn } +
            builtInVoices.filter { $0.language == code }
    }

    static func preferredLanguage(for storyText: String) -> StoryLanguage {
        let sample = String(storyText.prefix(4000))
        guard sample.split(whereSeparator: \.isWhitespace).count >= 10 else { return .preferred }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let language = recognizer.dominantLanguage, (hypotheses[language] ?? 0) >= 0.7 else { return .preferred }
        switch language {
        case .polish: return .polish
        case .english: return .english
        default: return .preferred
        }
    }
}
