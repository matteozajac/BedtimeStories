import FoundationModels

@Generable
struct GeneratedStoryBook: Codable, Sendable {
    @Guide(description: "A short original book title in the requested language.")
    var title: String
    @Guide(description: "One sentence describing this story in the requested language.")
    var summary: String
    @Guide(description: "Fully written chapters in order. Choose the count to fit the whole book's requested reading time and total word count. One connected story with consistent characters, a beginning, events, and a peaceful resolution in the last chapter.", .count(1...12))
    var chapters: [GeneratedBookChapter]
    @Guide(description: "A shared illustration brief in English, under 400 characters. Describe recurring characters' consistent appearance, the setting, and a warm pastel storybook palette. No artist names, written text, or unsafe content. Reuse this brief for cover and chapter pictures.")
    var illustrationGuide: String = ""
}

extension GeneratedStoryBook {
    static func schema(for request: StoryGenerationRequest) throws -> GenerationSchema {
        let chapter = DynamicGenerationSchema(name: "BookChapter", properties: [
            .init(name: "title", description: "A short distinct chapter title in \(request.language.promptName).", schema: .init(type: String.self)),
            .init(name: "text", description: "Fully written story prose, never an outline. This whole book needs \(request.targetWords) prose words. If you choose \(request.maximumChapters) chapters, write about \(request.targetWords / request.maximumChapters) words in EACH chapter; fewer chapters need more words each. At least 60 words per chapter. Continue previous events; the peaceful ending belongs only in the last chapter. Finish every sentence.", schema: .init(type: String.self))
        ])
        let book = DynamicGenerationSchema(name: "CompleteBook", properties: [
            .init(name: "title", description: "A short original title in \(request.language.promptName).", schema: .init(type: String.self)),
            .init(name: "summary", description: "One concise sentence in \(request.language.promptName).", schema: .init(type: String.self)),
            .init(name: "chapters", description: "One connected chronological story totaling \(request.targetWords) words. Choose 1–\(request.maximumChapters) chapters.", schema: .init(arrayOf: chapter, minimumElements: 1, maximumElements: request.maximumChapters)),
            .init(name: "illustrationGuide", description: "Shared illustration brief in English under 400 characters. Consistent recurring character appearances, setting, warm pastel storybook palette. No lettering or artist names.", schema: .init(type: String.self))
        ])
        return try GenerationSchema(root: book, dependencies: [])
    }
}
