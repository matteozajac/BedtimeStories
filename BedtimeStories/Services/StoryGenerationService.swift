import Foundation
import FirebaseVertexAI

class StoryGenerationService: ObservableObject {
    private let model: GenerativeModel
    
    init() {
        
        let jsonSchema = Schema.object(
            properties: [
                "title": .string(),
                "content": .string()
            ]
        )
        
        model = VertexAI.vertexAI().generativeModel(
            modelName: "gemini-2.0-flash",
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: jsonSchema
            )
        )
    }
    
    func generateStory(duration: ReadingDuration, description: String?, favoriteCharacters: String?) async throws -> Story {
        let prompt = buildPrompt(duration: duration, description: description, favoriteCharacters: favoriteCharacters)
        
        let response = try await model.generateContent(prompt)
        
        guard let text = response.text else {
            throw StoryGenerationError.noResponse
        }
        
        return try parseStoryFromResponse(text, duration: duration, description: description, favoriteCharacters: favoriteCharacters)
    }
    
    private func buildPrompt(duration: ReadingDuration, description: String?, favoriteCharacters: String?) -> String {
        var prompt = """
        Generate a bedtime story that is approximately \(duration.rawValue) minutes long when read aloud.

        Requirements:
        - The story should be calming and suitable for bedtime
        - Include gentle, peaceful themes
        - End with a soothing conclusion that helps children fall asleep
        - Provide the story content formatted as Markdown
        """
        
        if let description = description, !description.isEmpty {
            prompt += "\n- Story theme/description: \(description)"
        }
        
        if let characters = favoriteCharacters, !characters.isEmpty {
            prompt += "\n- Include these characters: \(characters)"
        }
        
        prompt += """
        """
        
        return prompt
    }
    
    private func parseStoryFromResponse(_ response: String, duration: ReadingDuration, description: String?, favoriteCharacters: String?) throws -> Story {
        guard let data = response.data(using: .utf8) else {
            throw StoryGenerationError.invalidResponse
        }
        
        do {
            let storyResponse = try JSONDecoder().decode(StoryResponse.self, from: data)
            // Use the generated content when creating the Story so it can be
            // shown in the UI and persisted to Firestore.
            return Story(
                title: storyResponse.title,
                content: storyResponse.content,
                duration: duration,
                description: description,
                favoriteCharacters: favoriteCharacters
            )
        } catch {
            throw StoryGenerationError.parsingFailed
        }
    }
}

struct StoryResponse: Codable {
    let title: String
    let content: String
}

enum StoryGenerationError: Error, LocalizedError {
    case noResponse
    case invalidResponse
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "No response from AI"
        case .invalidResponse:
            return "Invalid response format"
        case .parsingFailed:
            return "Failed to parse story"
        }
    }
}
