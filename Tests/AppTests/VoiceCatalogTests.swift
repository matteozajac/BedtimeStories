import Foundation
import Testing
@testable import BedtimeStories

@Suite @MainActor
struct VoiceCatalogTests {
    @Test func firstLanguageChoiceFollowsSupportedStoryText() {
        #expect(VoiceProfile.preferredLanguage(for: "Mały królik mieszkał w zielonym lesie. Każdego wieczoru patrzył na księżyc i słuchał cichego szumu drzew. Mama otuliła go miękkim kocykiem i opowiedziała mu bajkę o przyjaźni.") == .polish)
        #expect(VoiceProfile.preferredLanguage(for: "The little rabbit lived in a quiet forest. Every evening, he looked up at the moon and listened to the trees. His mother wrapped him in a soft blanket and told him a story about friendship.") == .english)
        #expect(VoiceProfile.preferredLanguage(for: "") == .preferred)
    }

    @Test func eachLanguageHasThreeDistinctAvailableStorytellers() {
        for language in StoryLanguage.allCases {
            let voices = VoiceProfile.available(for: language, personalVoices: [])
            #expect(voices.count == 3)
            #expect(Set(voices.map(\.id)).count == 3)
            #expect(voices.allSatisfy { $0.isBuiltIn && $0.status == "ready" && $0.narrationDescription != nil })
            #expect(voices.allSatisfy { $0.language == (language == .polish ? "pl-PL" : "en-US") })
        }
    }

    @Test func automaticSelectionPrefersAvailablePersonalVoiceAndPreservesExplicitChoice() {
        let parent = VoiceProfile(id: "parent", displayName: "Mama", language: "pl-PL", status: "ready")
        let pending = VoiceProfile(id: "pending", displayName: "Tata", language: "pl-PL", status: "processing")
        var preferences = NarrationDraftPreferences()
        preferences.language = .polish
        preferences.selectAvailableVoice(personalVoices: [pending, parent])
        #expect(preferences.voiceID == parent.id)
        preferences.voiceID = "builtin-pl-robin"
        preferences.selectAvailableVoice(personalVoices: [parent])
        #expect(preferences.voiceID == "builtin-pl-robin")
        preferences.language = .english
        preferences.selectAvailableVoice(personalVoices: [parent])
        #expect(preferences.voiceID == "builtin-en-luna")
    }

    @Test func removedOrUnavailableVoiceFallsBackWithinSelectedLanguage() {
        var preferences = NarrationDraftPreferences()
        preferences.language = .polish
        preferences.voiceID = "removed-parent"
        preferences.selectAvailableVoice(personalVoices: [])
        #expect(preferences.voiceID == "builtin-pl-luna")
    }

    @Test func storedPersonalChoiceSurvivesInitialMetadataLoading() {
        var preferences = NarrationDraftPreferences()
        preferences.language = .polish
        preferences.voiceID = "parent"
        preferences.selectAvailableVoice(personalVoices: [], personalVoicesLoaded: false)
        #expect(preferences.voiceID == "parent")
        let parent = VoiceProfile(id: "parent", displayName: "Mama", language: "pl-PL", status: "ready")
        preferences.selectAvailableVoice(personalVoices: [parent])
        #expect(preferences.voiceID == "parent")
        preferences.selectAvailableVoice(personalVoices: [], personalVoicesLoaded: true)
        #expect(preferences.voiceID == "builtin-pl-luna")
    }

    @Test func olderPreferencesKeepVoiceAndStyleAndNewLanguageRoundTrips() throws {
        // Swift's synthesized Codable stores UUID-keyed dictionaries as alternating
        // key/value arrays. This is the on-disk schema used before language existed.
        let chapterID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let legacy = Data(#"{"voiceID":"parent","defaultStyle":"gentle","styleOverrides":["11111111-1111-1111-1111-111111111111",{"0":"gentle"}],"chapterTextHashes":["11111111-1111-1111-1111-111111111111","original-text-hash"]}"#.utf8)
        var preferences = try JSONDecoder().decode(NarrationDraftPreferences.self, from: legacy)
        #expect(preferences.voiceID == "parent" && preferences.defaultStyle == .gentle)
        #expect(preferences.styleOverrides == [chapterID: [0: .gentle]])
        #expect(preferences.chapterTextHashes == [chapterID: "original-text-hash"])
        preferences.language = .polish
        let restored = try JSONDecoder().decode(NarrationDraftPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored == preferences)
    }
}
