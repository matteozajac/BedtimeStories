import SwiftUI

struct StoryDetailView: View {
    let story: Story
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(story.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                HStack {
                    Label(story.duration.displayText, systemImage: "clock")
                    Spacer()
                    Text("Created: \(story.createdAt, style: .date)")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                
                if let description = story.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                    }
                }
                
                if let characters = story.favoriteCharacters, !characters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Favorite Characters")
                            .font(.headline)
                        Text(characters)
                            .font(.body)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    // TODO: Implement story reading functionality
                }) {
                    Text("Start Reading")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}