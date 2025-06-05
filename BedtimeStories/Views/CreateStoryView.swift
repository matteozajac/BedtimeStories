import SwiftUI
import FirebaseVertexAI
import MarkdownUI

struct CreateStoryView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var selectedDuration = ReadingDuration.ten
    @State private var description = ""
    @State private var favoriteCharacters = ""
    @State private var isGenerating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatedContent: String?
    @StateObject private var storyService = StoryGenerationService()
    
    let onSave: (Story) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Story Details") {
                    TextField("Title", text: $title)
                    
                    Picker("Reading Duration", selection: $selectedDuration) {
                        ForEach(ReadingDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                }
                
                Section("Optional Details") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Favorite Characters", text: $favoriteCharacters)
                }
                
                Section {
                    Button(action: generateStory) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isGenerating ? "Generating..." : "Generate Story with AI")
                        }
                    }
                    .disabled(isGenerating)
                }
                
                if let content = generatedContent {
                    Section("Generated Story") {
                        Markdown(content)
                    }
                }
            }
            .navigationTitle("New Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let story = Story(
                            title: title,
                            content: generatedContent,
                            duration: selectedDuration,
                            description: description.isEmpty ? nil : description,
                            favoriteCharacters: favoriteCharacters.isEmpty ? nil : favoriteCharacters
                        )
                        onSave(story)
                        dismiss()
                    }
                    .disabled(title.isEmpty || (generatedContent?.isEmpty ?? true))
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func generateStory() {
        Task {
            await generateStoryAsync()
        }
    }
    
    @MainActor
    private func generateStoryAsync() async {
        isGenerating = true
        
        do {
            let generatedStory = try await storyService.generateStory(
                duration: selectedDuration,
                description: description.isEmpty ? nil : description,
                favoriteCharacters: favoriteCharacters.isEmpty ? nil : favoriteCharacters
            )
            
            title = generatedStory.title
            generatedContent = generatedStory.content
            isGenerating = false
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isGenerating = false
        }
    }
}
