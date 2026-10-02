import FoundationModels

@Generable
struct GeneratedIllustrationPrompt {
    @Guide(description: "One gentle visual scene in English, under 220 characters. Describe characters, their action and setting. No text, artist names or commentary. Keep the supplied recurring character appearances.")
    var scene: String
}
