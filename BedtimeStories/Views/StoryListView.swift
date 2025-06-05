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
                } else if stories.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No stories yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Tap 'Add Story' to create your first bedtime story")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(stories) { story in
                            NavigationLink(
                                destination: StoryDetailView(
                                    story: story,
                                    onDelete: { deleted in
                                        Task { await deleteStory(deleted) }
                                    }
                                )
                            ) {
                                StoryRowView(story: story)
                            }
                        }
                        .onDelete(perform: deleteStories)
                    }
                }
            }
            .navigationTitle("Bedtime Stories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Story") {
                        showingCreateStory = true
                    }
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

    @MainActor
    private func deleteStory(_ story: Story) async {
        guard let index = stories.firstIndex(where: { $0.id == story.id }) else {
            return
        }
        do {
            try await firestoreService.deleteStory(story)
            stories.remove(at: index)
        } catch {
            print("Error deleting story: \(error)")
        }
    }
}

struct StoryRowView: View {
    let story: Story
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.headline)
            
            Text(story.duration.displayText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let description = story.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Text("Created: \(story.createdAt, style: .date)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
