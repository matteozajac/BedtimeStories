import SwiftUI

struct StoryDetailView: View {
    let story: Story
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(story.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Story title: \(story.title)")
                    .accessibilityIdentifier("storyDetailTitle")
                
                HStack {
                    Label(story.duration.displayText, systemImage: "clock")
                        .accessibilityLabel("Reading duration: \(story.duration.displayText)")
                        .accessibilityIdentifier("storyDetailDuration")
                    Spacer()
                    Text("Created: \(story.createdAt, style: .date)")
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Created on \(story.createdAt, style: .date)")
                        .accessibilityIdentifier("storyDetailCreatedDate")
                }
                .font(.subheadline)
                
                if let description = story.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("descriptionHeader")
                        Text(description)
                            .font(.body)
                            .accessibilityLabel("Story description: \(description)")
                            .accessibilityIdentifier("storyDetailDescription")
                    }
                }
                
                if let characters = story.favoriteCharacters, !characters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Favorite Characters")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("charactersHeader")
                        Text(characters)
                            .font(.body)
                            .accessibilityLabel("Favorite characters: \(characters)")
                            .accessibilityIdentifier("storyDetailCharacters")
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
                .accessibilityLabel("Start reading \(story.title)")
                .accessibilityHint("Begins reading the bedtime story aloud")
                .accessibilityIdentifier("startReadingButton")
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("storyDetailView")
    }
}