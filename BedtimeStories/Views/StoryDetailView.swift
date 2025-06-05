import SwiftUI
import MarkdownUI

struct StoryDetailView: View {
    let story: Story
    let onDelete: (Story) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    
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
                if let content = story.content {
                    Markdown(content)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Story?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDelete(story)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
