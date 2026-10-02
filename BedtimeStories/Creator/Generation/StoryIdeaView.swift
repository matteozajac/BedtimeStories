import SwiftUI

struct StoryIdeaView: View {
    @Environment(\.scenePhase) private var phase
    @AppStorage("bookCreatorStoryIdea") private var description = ""
    @State private var language = StoryLanguage.preferred
    @State private var readerAge = StoryReaderAge.preschool
    @AppStorage("bookCreatorReadingMinutes") private var readingMinutes = 5
    @AppStorage("bookCreatorReadingPace") private var wordsPerMinute = StoryReadingLength.defaultWordsPerMinute
    @State private var mode = StoryGenerationMode.onDevice
    @State private var generationID: UUID?
    @State private var model: StoryGenerationModel
    @State private var availability: String?
    @FocusState private var editingDescription: Bool
    let openDraft: (BookDraft) -> Void

    init(store: BookDraftStore, openDraft: @escaping (BookDraft) -> Void) {
        _model = State(initialValue: StoryGenerationModel(store: store))
        self.openDraft = openDraft
    }

    var body: some View {
        Form {
            Section {
                TextField("A sleepy fox follows the stars home…", text: $description, axis: .vertical)
                    .lineLimit(5...10)
                    .focused($editingDescription)
                    .accessibilityLabel("Story description")
                    .accessibilityIdentifier("story-idea-description")
                Text("\(description.count) / 600 characters")
                    .font(.footnote)
                    .foregroundStyle(description.count > StoryGenerationRequest.maximumDescriptionLength ? .red : .secondary)
            } header: { Text("Your Story Idea") } footer: {
                Text("Describe the characters, setting, and what happens. Your idea is saved on this device.")
            }
            .disabled(model.working)

            Section("Story Options") {
                Picker("Language", selection: $language) {
                    ForEach(StoryLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Picker("Reader Age", selection: $readerAge) {
                    ForEach(StoryReaderAge.allCases) { age in Text(age.rawValue).tag(age) }
                }
                Stepper("Reading time: \(readingMinutes) minutes", value: $readingMinutes, in: 1...30)
                    .accessibilityIdentifier("story-reading-minutes")
                Stepper("Reading pace: \(wordsPerMinute) words/minute", value: $wordsPerMinute, in: 80...180, step: 10)
                    .accessibilityIdentifier("story-reading-pace")
                Text("About \(readingMinutes * wordsPerMinute) words for the whole book. Apple Intelligence chooses the chapter count; you can change it in the editor.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .disabled(model.working)

            Section {
                Picker("Create With", selection: $mode) {
                    ForEach(StoryGenerationMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.accessibilityIdentifier("story-generation-mode")
                if mode == .onDevice {
                    Label("Your description and story are processed on this device. No internet connection is needed once the model is ready.", systemImage: "iphone")
                } else {
                    Label("Your description and story context are sent to Apple's Private Cloud Compute to create the book. An internet connection is required.", systemImage: "cloud")
                }
                if let availability { Text(availability).foregroundStyle(.secondary) }
                if let durationWarning { Text(durationWarning).foregroundStyle(.secondary).accessibilityIdentifier("story-duration-warning") }
                Button("Check Availability", systemImage: "arrow.clockwise") { refreshAvailability() }
            } header: { Text("Processing") }
            .disabled(model.working)

            if model.working {
                Section {
                    ProgressView(model.saving ? "Saving the complete story…" : model.retrying ? "Checking the story’s length and completeness…" : "Writing your complete story…")
                    Button("Stop Creating", role: .cancel) { generationID = nil }
                        .accessibilityIdentifier("stop-story-generation")
                } footer: { Text("The entire book is written together and checked before it is saved to Your Drafts.") }
            } else {
                if let message = model.message {
                    Section {
                        Text(message).accessibilityIdentifier("story-generation-message")
                        if let draft = model.draft {
                            Text("Saved chapters: \(model.completedChapterCount)")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Open Saved Draft", systemImage: "doc.text") { openDraft(draft) }
                        }
                    }
                }
                Section {
                    Button(model.draft == nil ? "Create Story Draft" : "Create Another Draft", systemImage: "sparkles") {
                        editingDescription = false
                        generationID = UUID()
                    }
                    .disabled(availability != nil || durationWarning != nil || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.count > StoryGenerationRequest.maximumDescriptionLength)
                    .accessibilityIdentifier("generate-story-draft")
                } footer: {
                    Text("Apple Intelligence creates the title and chapter text. Review the story before sharing it with a child, then add pictures and narration.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create from an Idea")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshAvailability() }
        .onChange(of: language) { refreshAvailability() }
        .onChange(of: mode) { refreshAvailability() }
        .onChange(of: phase) { _, phase in
            if phase == .active { refreshAvailability() }
            else { generationID = nil }
        }
        .task(id: generationID) {
            guard generationID != nil else { return }
            let request = StoryGenerationRequest(description: description.trimmingCharacters(in: .whitespacesAndNewlines), language: language, readerAge: readerAge, readingMinutes: readingMinutes, wordsPerMinute: wordsPerMinute)
            await model.generate(request, mode: mode)
            if model.completed, !Task.isCancelled, let draft = model.draft { openDraft(draft) }
            refreshAvailability()
        }
    }

    private func refreshAvailability() {
        availability = model.unavailabilityReason(for: mode, language: language)
    }

    private var durationWarning: String? {
        if !(1...30).contains(readingMinutes) || !(80...180).contains(wordsPerMinute) { return StoryGenerationFailure.invalidDuration.errorDescription }
        return mode == .onDevice && readingMinutes * wordsPerMinute > StoryGenerationRequest.localWordLimit ? StoryGenerationFailure.localDurationTooLong.errorDescription : nil
    }
}
