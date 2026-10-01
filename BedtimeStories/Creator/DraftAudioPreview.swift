import AVFoundation
import Observation

@Observable @MainActor
final class DraftAudioPreview: NSObject, AVAudioPlayerDelegate {
    private(set) var playingPath: String?
    private(set) var loading = false
    var message: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var release: Task<Void, Never>?

    func toggle(path: String, draftID: UUID, store: BookDraftStore) {
        if playingPath == path { stop(); return }
        stop(); loading = true
        let previous = task
        task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let url = try await store.mediaURL(path, draftID: draftID)
                await self.release?.value
                try Task.checkCancellation()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                let activated = try await session.activate(options: [])
                try Task.checkCancellation()
                guard activated else { throw BookError.unavailable("Audio is unavailable.") }
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                guard player.play() else { throw BookError.unavailable("Audio is unavailable.") }
                self.player = player; self.playingPath = path
            } catch is CancellationError { self.releaseSession() }
            catch { self.message = String(localized: "The narration could not be played. Try again."); self.releaseSession() }
            self.loading = false
        }
    }

    func stop() {
        task?.cancel(); player?.stop(); player = nil; playingPath = nil; loading = false
        releaseSession()
    }

    private func releaseSession() {
        let previous = release
        release = Task { await previous?.value; _ = try? await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == id else { return }
            self.stop()
        }
    }

    isolated deinit { task?.cancel(); player?.stop() }
}
