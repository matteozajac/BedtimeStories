import SwiftUI

struct StoryListView: View {
    @State private var stories: [Story] = []
    @State private var showingCreateStory = false
    @State private var isLoading = true
    @StateObject private var firestoreService = FirestoreService()
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading stories...")
                        .accessibilityLabel("Loading your bedtime stories")
                        .accessibilityIdentifier("loadingIndicator")
                } else if stories.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Empty stories collection")
                            .accessibilityHidden(true) // Decorative image
                        Text("No stories yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("No bedtime stories available")
                        Text("Tap 'Add Story' to create your first bedtime story")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityHint("Use the Add Story button to create your first bedtime story")
                    }
                    .padding()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("emptyStoriesView")
                } else {
                    List {
                        ForEach(stories) { story in
                            NavigationLink(destination: StoryDetailView(story: story)) {
                                StoryRowView(story: story)
                            }
                            .accessibilityLabel("Story: \(story.title)")
                            .accessibilityHint("Tap to view story details")
                            .accessibilityIdentifier("storyItem_\(story.id)")
                        }
                        .onDelete(perform: deleteStories)
                    }
                    .accessibilityLabel("Bedtime stories list")
                    .accessibilityIdentifier("storiesList")
                }
            }
            .navigationTitle("Bedtime Stories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Story") {
                        showingCreateStory = true
                    }
                    .accessibilityLabel("Add new bedtime story")
                    .accessibilityHint("Opens the story creation form")
                    .accessibilityIdentifier("addStoryButton")
                }
            }
            .sheet(isPresented: $showingCreateStory) {
                CreateStoryView { newStory in
                    Task {
                        await saveStory(newStory)
                    }
                }
            }
            .task {
                await loadStories()
            }
            .refreshable {
                await loadStories()
            }
        }
    }
    
    @MainActor
    private func loadStories() async {
        isLoading = true
        do {
            stories = try await firestoreService.loadStories()
        } catch {
            print("Error loading stories: \(error)")
            // Could add error handling UI here
        }
        isLoading = false
    }
    
    @MainActor
    private func saveStory(_ story: Story) async {
        do {
            try await firestoreService.saveStory(story)
            stories.insert(story, at: 0) // Add to beginning since we sort by date desc
        } catch {
            print("Error saving story: \(error)")
            // Could add error handling UI here
        }
    }
    
    private func deleteStories(offsets: IndexSet) {
        for index in offsets {
            let story = stories[index]
            Task {
                do {
                    try await firestoreService.deleteStory(story)
                    await MainActor.run {
                        stories.remove(at: index)
                    }
                } catch {
                    print("Error deleting story: \(error)")
                }
            }
        }
    }
}

struct StoryRowView: View {
    let story: Story
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("storyTitle")
            
            Text(story.duration.displayText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityLabel("Reading duration: \(story.duration.displayText)")
                .accessibilityIdentifier("storyDuration")
            
            if let description = story.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel("Description: \(description)")
                    .accessibilityIdentifier("storyDescription")
            }
            
            Text("Created: \(story.createdAt, style: .date)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Created on \(story.createdAt, style: .date)")
                .accessibilityIdentifier("storyCreatedDate")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
