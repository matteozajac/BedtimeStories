import SwiftUI
import FirebaseVertexAI

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
                        .accessibilityLabel("Story title")
                        .accessibilityHint("Enter a title for your bedtime story")
                        .accessibilityIdentifier("storyTitleField")
                    
                    Picker("Reading Duration", selection: $selectedDuration) {
                        ForEach(ReadingDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                    .accessibilityLabel("Reading duration")
                    .accessibilityHint("Select how long the story should take to read")
                    .accessibilityIdentifier("durationPicker")
                }
                
                Section("Optional Details") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Story description")
                        .accessibilityHint("Add an optional description or theme for your story")
                        .accessibilityIdentifier("descriptionField")
                    
                    TextField("Favorite Characters", text: $favoriteCharacters)
                        .accessibilityLabel("Favorite characters")
                        .accessibilityHint("Enter character names to include in the story")
                        .accessibilityIdentifier("charactersField")
                }
                
                Section {
                    Button(action: generateStory) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .accessibilityHidden(true)
                            }
                            Text(isGenerating ? "Generating..." : "Generate Story with AI")
                        }
                    }
                    .disabled(isGenerating)
                    .accessibilityLabel(isGenerating ? "Generating story" : "Generate story with AI")
                    .accessibilityHint("Uses artificial intelligence to create a bedtime story based on your preferences")
                    .accessibilityIdentifier("generateStoryButton")
                }
                
                if let content = generatedContent {
                    Section("Generated Story") {
                        Text(content)
                            .font(.body)
                            .accessibilityLabel("Generated story content")
                            .accessibilityHint("This is the AI-generated story content")
                            .accessibilityIdentifier("generatedStoryContent")
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
                    .accessibilityLabel("Cancel story creation")
                    .accessibilityHint("Discards changes and returns to the stories list")
                    .accessibilityIdentifier("cancelButton")
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
                    .disabled(title.isEmpty)
                    .accessibilityLabel("Save story")
                    .accessibilityHint(title.isEmpty ? "Enter a title to save the story" : "Saves the story to your collection")
                    .accessibilityIdentifier("saveStoryButton")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
                    .accessibilityLabel("Acknowledge error")
                    .accessibilityIdentifier("errorOkButton")
            } message: {
                Text(errorMessage)
                    .accessibilityLabel("Error message: \(errorMessage)")
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
