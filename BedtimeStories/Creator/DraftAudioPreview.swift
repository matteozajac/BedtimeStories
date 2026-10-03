import AVFoundation
import MZAppFoundation
import Observation

@Observable @MainActor
final class DraftAudioPreview: NSObject, AVAudioPlayerDelegate {
    private(set) var playingPath: String?
    private(set) var loading = false
    var message: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var release: Task<Void, Never>?
    @ObservationIgnored private let logger: any AppLogging

    init(logger: any AppLogging = AppLog.logger) {
        self.logger = logger
        super.init()
    }

    func toggle(path: String, draftID: UUID, store: BookDraftStore) {
        if playingPath == path { stop(); return }
        stop(); loading = true
        logger.trace("Draft narration preview loading started", category: "playback")
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
                self.logger.log(LogEntry("Draft narration preview started", level: .debug, category: "playback"))
            } catch is CancellationError {
                self.logger.trace("Draft narration preview cancelled", category: "playback")
                self.releaseSession()
            }
            catch {
                self.logger.error("Draft narration preview failed", error: error, category: "playback")
                self.message = String(localized: "The narration could not be played. Try again.")
                self.releaseSession()
            }
            self.loading = false
        }
    }

    func stop() {
        task?.cancel(); player?.stop(); player = nil; playingPath = nil; loading = false
        releaseSession()
    }

    private func releaseSession() {
        let previous = release
        release = Task { [logger] in
            await previous?.value
            do { _ = try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) }
            catch is CancellationError { logger.trace("Preview audio session release cancelled", category: "playback") }
            catch { logger.warning("Preview audio session release failed", error: error, category: "playback") }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == id else { return }
            if !flag { self.logger.error("Draft narration preview did not finish successfully", category: "playback") }
            self.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        let snapshot = error.map { ErrorSnapshot($0) }
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == id else { return }
            self.logger.log(LogEntry("Draft narration decoding failed", level: .error, category: "playback", error: snapshot))
            self.message = String(localized: "The narration could not be played. Try again.")
            self.stop()
        }
    }

    isolated deinit { task?.cancel(); player?.stop() }
}
