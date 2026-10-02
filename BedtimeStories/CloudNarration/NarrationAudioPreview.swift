import AVFoundation
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
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                await release?.value
                try Task.checkCancellation()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                let activated = try await session.activate(options: [])
                try Task.checkCancellation()
                guard activated else { throw BookError.unavailable("Audio is unavailable.") }
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.delegate = self
                guard audio.play() else { throw BookError.unavailable("Audio is unavailable.") }
                player = audio; playingURL = url
            } catch is CancellationError { releaseSession() }
            catch { message = String(localized: "The preview could not be played. Try again."); releaseSession() }
            loading = false
        }
    }

    func stop() {
        operation?.cancel(); player?.stop(); player = nil; playingURL = nil; loading = false
        releaseSession()
    }

    private func releaseSession() {
        let pending = release
        release = Task { await pending?.value; _ = try? await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identifier else { return }
            stop()
        }
    }

    isolated deinit { operation?.cancel(); player?.stop() }
}
