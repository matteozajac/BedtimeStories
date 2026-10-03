import AVFoundation
import MZAppFoundation
import Observation

@Observable @MainActor
final class NarrationAudioPreview: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    private(set) var loading = false
    var message: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var release: Task<Void, Never>?

    func toggle(_ url: URL) {
        if playingURL == url { stop(); return }
        stop(); loading = true
        let diagnostic = CloudNarrationLogOperation(name: "narration_audio_preview")
        AppLog.trace("Narration audio preview started", category: "cloud_narration", metadata: diagnostic.metadata)
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                await release?.value
                try Task.checkCancellation()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                AppLog.trace("Narration preview audio session activation started", category: "cloud_narration", metadata: diagnostic.metadata)
                let activated = try await session.activate(options: [])
                try Task.checkCancellation()
                guard activated else { throw BookError.unavailable("Audio is unavailable.") }
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.delegate = self
                guard audio.play() else { throw BookError.unavailable("Audio is unavailable.") }
                player = audio; playingURL = url
                AppLog.debug("Narration audio preview playing", category: "cloud_narration", metadata: diagnostic.metadata)
            } catch is CancellationError {
                AppLog.trace("Narration audio preview cancelled", category: "cloud_narration", metadata: diagnostic.metadata)
                releaseSession()
            } catch {
                AppLog.error("Narration audio preview failed", error: error, category: "cloud_narration", metadata: diagnostic.metadata)
                message = String(localized: "The preview could not be played. Try again."); releaseSession()
            }
            loading = false
        }
    }

    func stop() {
        if player != nil || loading { AppLog.trace("Narration audio preview stopping", category: "cloud_narration") }
        operation?.cancel(); player?.stop(); player = nil; playingURL = nil; loading = false
        releaseSession()
    }

    private func releaseSession() {
        let pending = release
        release = Task {
            await pending?.value
            do {
                _ = try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation])
                AppLog.trace("Narration preview audio session deactivated", category: "cloud_narration")
            } catch { AppLog.warning("Narration preview audio session deactivation failed", error: error, category: "cloud_narration") }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identifier else { return }
            if flag { AppLog.debug("Narration audio preview finished", category: "cloud_narration") }
            else { AppLog.error("Narration audio preview finished unsuccessfully", category: "cloud_narration") }
            stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identifier = ObjectIdentifier(player)
        let snapshot = error.map { ErrorSnapshot($0) }
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identifier else { return }
            AppLog.logger.log(LogEntry("Narration audio preview decoding failed", level: .error, category: "cloud_narration", error: snapshot, source: snapshot?.source))
            self.message = String(localized: "The preview could not be played. Try again.")
            self.stop()
        }
    }

    isolated deinit { operation?.cancel(); player?.stop() }
}
