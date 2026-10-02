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
                VStack(spacing: 28) {
                    VStack(spacing: 18) {
                        RecordingOrb(level: recorder.level, recording: recorder.recording,
                                     systemImage: recorder.ready ? "waveform" : recorder.paused ? "pause.fill" : "mic.fill")
                        VStack(spacing: 4) {
                            Text(recorder.ready ? "Review Your Take" : recorder.recording ? "Recording" : recorder.paused ? "Paused" : "Record Your Story")
                                .storyFont(.title2, weight: .bold).foregroundStyle(recorder.recording ? Theme.recording : Theme.ink)
                            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                                .font(.system(size: 44, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                                .contentTransition(.numericText())
                                .accessibilityLabel("Recording duration")
                        }
                    }
                    if recorder.busy || saving { ProgressView("Preparing audio…") }
                    if let message = recorder.message {
                        VStack(spacing: 12) {
                            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if recorder.permissionDenied {
                                Button("Open Settings", systemImage: "gearshape") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }
                                .buttonStyle(.storySoft)
                            }
                        }
                        .frame(maxWidth: .infinity).storyCard(padding: 18)
                    }
                    controls
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Eyebrow("Your Chapter")
                            Text(text).storyFont(.title3).lineSpacing(8).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        .storyCard(padding: 24)
                    } else {
                        Text("Speak in your own words. Your recording stays on this device until you add the book to your library.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background { StoryBackground() }
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
        VStack(spacing: 12) {
            if recorder.ready {
                Button("Use Recording", systemImage: "checkmark") {
                    guard let url = recorder.url else { return }
                    saving = true
                    Task {
                        if await accept(url) { recorder.cancel(); dismiss() }
                        else { saveFailed = true }
                        saving = false
                    }
                }.buttonStyle(.storyProminent(fullWidth: true)).accessibilityIdentifier("use-recording")
                Button(recorder.playing ? "Stop Preview" : "Play Take", systemImage: recorder.playing ? "stop.fill" : "play.fill", action: recorder.togglePreview)
                    .buttonStyle(.storySoft(fullWidth: true))
                Button("Record Again", systemImage: "arrow.counterclockwise") { rerecording = true }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .confirmationDialog("Replace this take?", isPresented: $rerecording, titleVisibility: .visible) {
                        Button("Record Again", role: .destructive, action: recorder.start)
                    }
            } else if recorder.recording || recorder.paused {
                Button("Finish Recording", systemImage: "stop.fill", action: recorder.finish)
                    .buttonStyle(.storyRecord).accessibilityIdentifier("finish-recording")
                Button(recorder.paused ? "Resume Recording" : "Pause Recording", systemImage: recorder.paused ? "mic.fill" : "pause.fill") {
                    if recorder.paused { recorder.resume() } else { recorder.pause() }
                }.buttonStyle(.storySoft(fullWidth: true))
            } else {
                Button("Start Recording", systemImage: "mic.fill", action: recorder.start)
                    .buttonStyle(.storyRecord).accessibilityIdentifier("start-recording")
            }
        }
        .frame(maxWidth: 400)
        .disabled(recorder.busy || saving)
    }
}

/// Soft rings that swell with the microphone level while recording.
private struct RecordingOrb: View {
    let level: Double
    let recording: Bool
    let systemImage: String

    var body: some View {
        let color = recording ? Theme.recording : Theme.accent
        ZStack {
            Circle().fill(color.opacity(0.08)).frame(width: 200, height: 200)
                .scaleEffect(recording ? 0.8 + min(1, level) * 0.35 : 0.8)
            Circle().fill(color.opacity(0.14)).frame(width: 156, height: 156)
                .scaleEffect(recording ? 0.88 + min(1, level) * 0.2 : 0.88)
            Circle().fill(color).frame(width: 108, height: 108)
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: color.opacity(0.4), radius: 18, y: 8)
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(recording ? .white : Theme.onAccent)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 200, height: 200)
        .animation(.easeOut(duration: 0.15), value: level)
        .animation(.spring(duration: 0.4), value: recording)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue(recording ? Text(min(1, level), format: .percent.precision(.fractionLength(0))) : Text(verbatim: ""))
        .accessibilityHidden(!recording)
    }
}
