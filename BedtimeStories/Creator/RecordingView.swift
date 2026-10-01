import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    let text: String
    let accept: @MainActor (URL) async -> Bool
    @State private var recorder = NarrationRecorder()
    @State private var discarding = false
    @State private var rerecording = false
    @State private var saving = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Label(recorder.ready ? "Review Your Take" : recorder.recording ? "Recording" : recorder.paused ? "Paused" : "Record Your Story",
                        systemImage: recorder.recording ? "record.circle" : "mic")
                        .font(.title2.bold()).foregroundStyle(recorder.recording ? .red : .primary)
                    Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.largeTitle.monospacedDigit()).accessibilityLabel("Recording duration")
                    if recorder.recording {
                        ProgressView(value: recorder.level).tint(.red).accessibilityLabel("Microphone level")
                    }
                    if recorder.busy || saving { ProgressView("Preparing audio…") }
                    if let message = recorder.message {
                        Text(message).font(.subheadline).foregroundStyle(.secondary)
                        if recorder.permissionDenied {
                            Button("Open Settings", systemImage: "gearshape") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                    controls
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Chapter").font(.headline)
                            Text(text).font(.title3).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.padding().background(.quaternary, in: .rect(cornerRadius: 16))
                    } else {
                        Text("Speak in your own words. Your recording stays on this device until you add the book to your library.")
                            .foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
            .navigationTitle("Narration").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if recorder.hasTake { discarding = true }
                        else { recorder.cancel(); dismiss() }
                    }.disabled(saving || recorder.finishing)
                    .confirmationDialog("Discard this take?", isPresented: $discarding, titleVisibility: .visible) {
                        Button("Discard Take", role: .destructive) { recorder.cancel(); dismiss() }
                    } message: { Text("The narration already saved in your chapter will be kept.") }
                }
            }
            .interactiveDismissDisabled(recorder.hasTake || recorder.busy || saving)
            .onChange(of: phase) { _, new in if new != .active { recorder.pauseForInterruption() } }
            .onDisappear { recorder.cancel() }
            .alert("Unable to save recording", isPresented: $saveFailed) { } message: { Text("Your take is still here. Try again before closing the recorder.") }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if recorder.ready {
                Button(recorder.playing ? "Stop Preview" : "Play Take", systemImage: recorder.playing ? "stop.fill" : "play.fill", action: recorder.togglePreview)
                    .buttonStyle(.bordered)
                Button("Use Recording", systemImage: "checkmark") {
                    guard let url = recorder.url else { return }
                    saving = true
                    Task {
                        if await accept(url) { recorder.cancel(); dismiss() }
                        else { saveFailed = true }
                        saving = false
                    }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("use-recording")
                Button("Record Again", systemImage: "arrow.counterclockwise") { rerecording = true }
                    .confirmationDialog("Replace this take?", isPresented: $rerecording, titleVisibility: .visible) {
                        Button("Record Again", role: .destructive, action: recorder.start)
                    }
            } else if recorder.recording || recorder.paused {
                Button(recorder.paused ? "Resume Recording" : "Pause Recording", systemImage: recorder.paused ? "mic.fill" : "pause.fill") {
                    if recorder.paused { recorder.resume() } else { recorder.pause() }
                }.buttonStyle(.bordered)
                Button("Finish Recording", systemImage: "stop.fill", action: recorder.finish)
                    .buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("finish-recording")
            } else {
                Button("Start Recording", systemImage: "mic.fill", action: recorder.start)
                    .buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("start-recording")
            }
        }.controlSize(.large).disabled(recorder.busy || saving)
    }
}
