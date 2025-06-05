import Foundation
import FirebaseFirestore

class FirestoreService: ObservableObject {
    private let db = Firestore.firestore()
    private let collection = "stories"
    
    func saveStory(_ story: Story) async throws {
        let data: [String: Any] = [
            "title": story.title,
            "content": story.content ?? "",
            "duration": story.duration.rawValue,
            "description": story.description ?? "",
            "favoriteCharacters": story.favoriteCharacters ?? "",
            "createdAt": story.createdAt
        ]
        
        try await db.collection(collection).document(story.id.uuidString).setData(data)
    }
    
    func loadStories() async throws -> [Story] {
        let snapshot = try await db.collection(collection)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { document -> Story? in
            let data = document.data()
            
            guard let title = data["title"] as? String,
                  let durationValue = data["duration"] as? Int,
                  let duration = ReadingDuration(rawValue: durationValue),
                  let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
                return nil
            }
            
            let content = data["content"] as? String
            let description = data["description"] as? String
            let favoriteCharacters = data["favoriteCharacters"] as? String
            
            return Story(
                id: UUID(uuidString: document.documentID) ?? UUID(),
                title: title,
                content: content?.isEmpty == true ? nil : content,
                duration: duration,
                description: description?.isEmpty == true ? nil : description,
                favoriteCharacters: favoriteCharacters?.isEmpty == true ? nil : favoriteCharacters,
                createdAt: createdAt
            )
        }
    }
    
    func deleteStory(_ story: Story) async throws {
        try await db.collection(collection).document(story.id.uuidString).delete()
    }
}
