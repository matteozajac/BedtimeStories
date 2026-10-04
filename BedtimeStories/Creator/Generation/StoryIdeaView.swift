import AuthenticationServices
import SwiftUI

struct StoryIdeaView: View {
    @Environment(OperationCenter.self) private var operations
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var phase
    @AppStorage("bookCreatorStoryIdea") private var description = ""
    @State private var language = StoryLanguage.preferred
    @State private var readerAge = StoryReaderAge.preschool
    @AppStorage("bookCreatorReadingMinutes") private var readingMinutes = 5
    @AppStorage("bookCreatorReadingPace") private var wordsPerMinute = StoryReadingLength.defaultWordsPerMinute
    @State private var mode = StoryGenerationMode.onDevice
    @State private var generationID: UUID?
    @State private var operationID: String?
    @State private var model: StoryGenerationModel
    @State private var cloudProcessingAccepted = false
    private let cloud: CloudNarrationModel
    @State private var availability: String?
    @State private var lastAvailabilityState: String?
    @FocusState private var editingDescription: Bool
    let openDraft: (BookDraft) -> Void

    init(store: BookDraftStore, cloud: CloudNarrationModel, openDraft: @escaping (BookDraft) -> Void) {
        self.cloud = cloud
        _mode = State(initialValue: StoryLanguage.preferred == .polish && cloud.isConfigured && cloud.isEnabled ? .gemini : .onDevice)
        _model = State(initialValue: StoryGenerationModel(store: store, generator: StoryGenerator(cloud: cloud)))
        self.openDraft = openDraft
    }

    var body: some View {
        Form {
            Section {
                TextField("A sleepy fox follows the stars home…", text: $description, axis: .vertical)
                    .lineLimit(5...10)
                    .storyFont(.body)
                    .focused($editingDescription)
                    .accessibilityLabel("Story description")
                    .accessibilityIdentifier("story-idea-description")
                Text("\(description.count) / 600 characters")
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(description.count > StoryGenerationRequest.maximumDescriptionLength ? Theme.recording : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } header: { Text("Your Story Idea") } footer: {
                Text("Describe the characters, setting, and what happens. Your idea is saved on this device.")
            }
            .listRowBackground(Theme.surface)
            .disabled(generationWorking)

            Section("Story Options") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Language")
                    Picker("Language", selection: $language) {
                        ForEach(StoryLanguage.allCases) { language in Text(language.title).tag(language) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reader Age")
                    Picker("Reader Age", selection: $readerAge) {
                        ForEach(StoryReaderAge.allCases) { age in Text(age.rawValue).tag(age) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                .padding(.vertical, 4)
                Stepper("Reading time: \(readingMinutes) minutes", value: $readingMinutes, in: 1...30)
                    .accessibilityIdentifier("story-reading-minutes")
                Stepper("Reading pace: \(wordsPerMinute) words/minute", value: $wordsPerMinute, in: 80...180, step: 10)
                    .accessibilityIdentifier("story-reading-pace")
                Text("About \(readingMinutes * wordsPerMinute) words for the whole book. The story model chooses the chapter count; you can change it in the editor.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(Theme.surface)
            .disabled(generationWorking)

            Section {
                Picker("Create With", selection: $mode) {
                    ForEach(StoryGenerationMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.accessibilityIdentifier("story-generation-mode")
                if mode == .onDevice {
                    Label("Your description and story are processed on this device. No internet connection is needed once the model is ready.", systemImage: "iphone")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if mode == .gemini {
                    Label("Gemini writes stories in Polish and English through our server. An internet connection and Apple sign-in are required.", systemImage: "sparkles")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Toggle("I agree to send my story idea to Gemini", isOn: $cloudProcessingAccepted)
                        .accessibilityIdentifier("gemini-story-consent")
                    Text("Your idea, reader age, language and reading time are sent through our server to Google Gemini. Processing may take place outside Europe. Our server temporarily keeps your idea and completed story for up to 24 hours so creation can finish while you are away. The finished draft is saved on this device. Avoid personal or sensitive details.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Your description and story context are sent to Apple's Private Cloud Compute to create the book. An internet connection is required.", systemImage: "cloud")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let availability { Text(availability).foregroundStyle(.secondary) }
                if let durationWarning { Text(durationWarning).foregroundStyle(.secondary).accessibilityIdentifier("story-duration-warning") }
                Button("Check Availability", systemImage: "arrow.clockwise") { refreshAvailability() }
            } header: { Text("Processing") }
            .listRowBackground(Theme.surface)
            .disabled(generationWorking)

            if mode == .gemini, cloud.isConfigured, cloud.isEnabled, cloud.userID == nil {
                Section {
                    Text("Sign in with Apple to create a story with Gemini.")
                    SignInWithAppleButton(.signIn, onRequest: cloud.prepareAppleSignIn, onCompletion: cloud.handleAppleSignIn)
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50).clipShape(.capsule)
                        .disabled(cloud.isWorking)
                        .accessibilityIdentifier("story-apple-sign-in")
                    if let message = cloud.message { Text(message).foregroundStyle(.secondary) }
                }
                .listRowBackground(Theme.surface)
            }

            if generationWorking {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.title.weight(.semibold)).foregroundStyle(Theme.glow)
                            .symbolEffect(.variableColor.iterative.reversing)
                            .frame(width: 48)
                            .accessibilityHidden(true)
                        Text(model.saving ? "Saving the complete story…" : model.retrying ? "Checking the story’s length and completeness…" : "Writing your complete story…")
                            .storyFont(.headline, weight: .semibold).foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 8)
                    Button("Stop Creating", role: .cancel) {
                        AppLog.debug("Story creation stop requested", category: "creator", metadata: ["mode": .string(mode.rawValue)])
                        if let operationID { operations.cancel(id: operationID) }
                        generationID = nil
                    }
                        .accessibilityIdentifier("stop-story-generation")
                } footer: {
                    Text("The entire book is written together and checked before it is saved to Your Drafts.")
                    if mode == .gemini { Text("You can leave this screen. We will let you know when your story is ready. Stop Creating cancels the job; an idea already being processed may finish on the server.") }
                }
                .listRowBackground(Theme.surface)
            } else {
                if let message = model.message ?? operations.operations.first(where: { $0.id == operationID })?.message {
                    Section {
                        Text(message).accessibilityIdentifier("story-generation-message")
                        if let draft = model.draft {
                            Text("Saved chapters: \(model.completedChapterCount)")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Open Saved Draft", systemImage: "doc.text") {
                                AppLog.debug("Generated draft editor opening requested", category: "creator", metadata: ["chapter_count": .integer(draft.chapters.count)])
                                openDraft(draft)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                Section {
                    Button(model.draft == nil ? "Create Story Draft" : "Create Another Draft", systemImage: "sparkles") {
                        editingDescription = false
                        startGeneration()
                    }
                    .buttonStyle(.storyProminent(fullWidth: true))
                    .disabled((mode == .gemini && !cloudProcessingAccepted) || availability != nil || durationWarning != nil || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.count > StoryGenerationRequest.maximumDescriptionLength)
                    .accessibilityIdentifier("generate-story-draft")
                } footer: {
                    Text("Your chosen model creates the title and chapter text. Review the story before sharing it with a child, then add pictures and narration.")
                        .padding(.top, 8)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .storyFormStyle()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create from an Idea")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            AppLog.debug("Story idea creator opened", category: "creator", metadata: ["mode": .string(mode.rawValue)])
            refreshAvailability()
        }
        .onDisappear { AppLog.trace("Story idea creator closed", category: "creator", metadata: ["generation_running": .bool(generationWorking)]) }
        .onChange(of: language) { refreshAvailability() }
        .onChange(of: cloud.userID) {
            cloudProcessingAccepted = false
            generationID = nil
            refreshAvailability()
        }
        .onChange(of: cloud.isConfigured) { refreshAvailability() }
        .onChange(of: cloud.isEnabled) { refreshAvailability() }
        .onChange(of: mode) { refreshAvailability() }
        .onChange(of: readingMinutes) { _, value in
            AppLog.debug("Story reading time changed", category: "creator", metadata: ["reading_minutes": .integer(value)])
            refreshAvailability()
        }
        .onChange(of: wordsPerMinute) { _, value in
            AppLog.debug("Story reading pace changed", category: "creator", metadata: ["words_per_minute": .integer(value)])
            refreshAvailability()
        }
        .onChange(of: phase) { _, phase in if phase == .active { refreshAvailability() } }
        .onChange(of: operations.operations) { _, _ in
            guard let operationID, let operation = operations.operations.first(where: { $0.id == operationID }) else { return }
            if operation.state == .ready, case .draft(let id) = operation.destination {
                Task { if let draft = try? await model.store.load(id) { openDraft(draft) } }
                self.operationID = nil
            }
        }

    }

    private func startGeneration() {
        let request = StoryGenerationRequest(description: description.trimmingCharacters(in: .whitespacesAndNewlines), language: language,
            readerAge: readerAge, readingMinutes: readingMinutes, wordsPerMinute: wordsPerMinute, cloudProcessingAccepted: cloudProcessingAccepted)
        let selectedMode = mode
        let id = UUID().uuidString.lowercased()
        let draftID = UUID(uuidString: id)!
        operationID = id
        generationID = draftID
        if selectedMode == .gemini {
            operations.start(kind: .storyGeneration, title: String(localized: "Writing your story"), subtitle: String(localized: "Writing your complete story…"),
                destination: .draft(draftID), ownerID: cloud.userID, id: id) { operationID in
                operations.trackRemoteSubmission(operationID, remoteID: id)
                let remoteID = try await cloud.startStory(request: request, requestID: id)
                operations.attachRemote(operationID, remoteID: remoteID)
                cloud.refreshOperations()
            }
            operations.setReadingPace(id, value: request.wordsPerMinute)
        } else {
            operations.start(kind: .storyGeneration, title: String(localized: "Writing your story"), subtitle: String(localized: "Writing your complete story…"),
                destination: .draft(draftID), id: id) { operationID in
                await model.generate(request, mode: selectedMode)
                if let draft = model.draft { operations.update(operationID, destination: .draft(draft.id), title: draft.title) }
                guard model.completed, let draft = model.draft else {
                    if Task.isCancelled { throw CancellationError() }
                    throw StoryGenerationFailure.unavailable(model.message ?? String(localized: "The story could not be completed. Try again with a shorter reading time or a simpler idea."))
                }
                operations.update(operationID, progress: 1, destination: .draft(draft.id), title: draft.title)
            }
        }
        Task { await operations.requestNotificationAuthorization() }
    }
    private var generationWorking: Bool {
        guard let operationID else { return false }
        return operations.operations.first(where: { $0.id == operationID })?.isActive == true
    }

    private func refreshAvailability() {
        availability = model.unavailabilityReason(for: mode, language: language)
        let state = "\(mode.rawValue):\(language.rawValue):\(availability == nil):\(durationWarning == nil)"
        if state != lastAvailabilityState {
            lastAvailabilityState = state
            AppLog.debug("Story creation availability changed", category: "creator", metadata: ["mode": .string(mode.rawValue),
                "language": .string(language.rawValue), "model_available": .bool(availability == nil), "duration_supported": .bool(durationWarning == nil)])
        }
    }

    private var durationWarning: String? {
        if !(1...30).contains(readingMinutes) || !(80...180).contains(wordsPerMinute) { return StoryGenerationFailure.invalidDuration.errorDescription }
        return mode == .onDevice && readingMinutes * wordsPerMinute > StoryGenerationRequest.localWordLimit ? StoryGenerationFailure.localDurationTooLong.errorDescription : nil
    }
}
