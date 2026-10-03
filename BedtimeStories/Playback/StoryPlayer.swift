import AVFoundation
import MediaPlayer
import MZAppFoundation
import Observation
import UIKit

@Observable @MainActor
final class StoryPlayer {
    private(set) var book: LibraryBook?
    private(set) var trackIndex = 0
    private(set) var elapsed = 0.0
    private(set) var duration = 0.0
    private(set) var playing = false
    private(set) var loading = false
    private(set) var error: String?
    private(set) var speed: Float = 1
    private(set) var sleepLabel: String?
    @ObservationIgnored private var audio = AVPlayer()
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var completionObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptions: [NSObjectProtocol] = []
    @ObservationIgnored private var commandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var repository: LibraryRepository?
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var progress: LocalProgress?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var sleepBoundary: Double?
    @ObservationIgnored private var lastSave = 0.0
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var interruptionWasPlaying = false
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private let logger: any AppLogging

    init(logger: any AppLogging = AppLog.logger) {
        self.logger = logger
        timeObserver = audio.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        let center = NotificationCenter.default
        interruptions.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            guard context?.interruptionContext != nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.log(LogEntry("Playback interrupted", level: .notice, category: "playback", metadata: self.diagnosticMetadata))
                self.interruptionWasPlaying = self.playing || self.wantsPlayback
                self.pause()
            }
        })
        interruptions.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            let shouldResume = context?.recommendation == .shouldResume
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.debug("Playback interruption resumption recommendation received", category: "playback", metadata: self.diagnosticMetadata.merging(["should_resume": .bool(shouldResume), "was_playing": .bool(self.interruptionWasPlaying)]) { _, new in new })
                if self.interruptionWasPlaying && shouldResume { self.resume() }
                self.interruptionWasPlaying = false
            }
        })
        interruptions.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                if let reason { self?.logger.trace("Playback audio route changed", category: "playback", metadata: ["reason_code": .integer(Int(reason))]) }
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
        interruptions.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause(); self?.resetEngine()
                self?.logger.log(LogEntry("Audio services reset", level: .warning, category: "playback"))
                self?.error = String(localized: "Audio was interrupted. Tap Play to reload the recording.")
            }
        })
        registerCommands()
    }

    var tracks: [AudioTrack] { book.map { AudioTrack.tracks(for: $0.manifest) } ?? [] }
    var chapterTitle: String {
        if let book, book.manifest.audio != nil, let chapter = AudioTrack.chapter(at: elapsed, in: book.manifest) { return chapter.title ?? book.manifest.title }
        return tracks.indices.contains(trackIndex) ? tracks[trackIndex].title : book?.manifest.title ?? ""
    }
    var currentChapterID: UUID? {
        guard let book else { return nil }
        return book.manifest.audio != nil ? AudioTrack.chapter(at: elapsed, in: book.manifest)?.id : tracks[safe: trackIndex]?.chapterID
    }
    var canSleepAtChapterEnd: Bool {
        guard let book else { return false }
        return book.manifest.audio == nil ? !tracks.isEmpty : AudioTrack.nextBoundary(after: elapsed, in: book.manifest, duration: duration) != nil
    }

    private var diagnosticMetadata: [String: TelemetryValue] {
        var fields: [String: TelemetryValue] = ["diagnostic_operation_id": .string(generation.uuidString), "track_index": .integer(trackIndex),
            "track_count": .integer(tracks.count), "elapsed_seconds": .double(elapsed), "duration_seconds": .double(duration),
            "speed": .double(speed.isFinite ? Double(speed) : 0), "playing": .bool(playing), "loading": .bool(loading)]
        if let book { fields["book_id"] = .string(book.id.uuidString) }
        if let chapterID = currentChapterID { fields["chapter_id"] = .string(chapterID.uuidString) }
        return fields
    }

    func restore(book: LibraryBook, repository: LibraryRepository, root: URL, progress: LocalProgress) {
        self.book = book; self.repository = repository; self.root = root; self.progress = progress
        let position = progress.playback(book.id)
        trackIndex = tracks.firstIndex { $0.chapterID == position?.chapterID } ?? 0
        elapsed = max(0, position?.seconds ?? 0)
        logger.debug("Playback position restored", category: "playback", metadata: diagnosticMetadata.merging(["has_saved_position": .bool(position != nil)]) { _, new in new })
    }

    func play(book: LibraryBook, chapter: BookChapter?, repository: LibraryRepository, root: URL, progress: LocalProgress) {
        if self.book?.id != book.id || self.book?.manifest != book.manifest {
            stop()
            restore(book: book, repository: repository, root: root, progress: progress)
        } else {
            self.repository = repository; self.root = root; self.progress = progress
        }
        logger.debug("Book playback requested", category: "playback", metadata: diagnosticMetadata.merging(["chapter_selected": .bool(chapter != nil)]) { _, new in new })
        error = nil
        if let chapter {
            cancelSleep()
            if book.manifest.audio != nil, let start = chapter.startTime { load(index: 0, at: start, autoplay: true) }
            else if let index = tracks.firstIndex(where: { $0.chapterID == chapter.id }) { load(index: index, at: 0, autoplay: true) }
            else { logger.warning("Selected chapter has no playable recording", category: "playback", metadata: diagnosticMetadata) }
        } else if audio.currentItem != nil { resume() }
        else { load(index: trackIndex, at: elapsed, autoplay: true) }
    }

    func toggle() { if playing || wantsPlayback { pause() } else { resume() } }

    func resume() {
        guard book != nil else {
            logger.warning("Playback resume ignored because no book is selected", category: "playback")
            return
        }
        logger.trace("Playback resume requested", category: "playback", metadata: diagnosticMetadata)
        error = nil
        wantsPlayback = true
        if loading {
            logger.trace("Playback resume waits for recording load", category: "playback", metadata: diagnosticMetadata)
            return
        }
        if audio.currentItem == nil { load(index: trackIndex, at: elapsed, autoplay: true); return }
        if duration > 0, elapsed >= duration - 0.2 { seek(0) }
        let token = generation
        let previous = sessionTask
        logger.trace("Playback audio session activation requested", category: "playback")
        sessionTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == token, self.wantsPlayback else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
                let activated = try await AVAudioSession.sharedInstance().activate(options: [])
                guard self.generation == token, self.wantsPlayback else { return }
                guard activated else { throw BookError.unavailable("Audio is unavailable.") }
                self.audio.playImmediately(atRate: self.speed); self.playing = true; self.updateNowPlaying()
                self.logger.log(LogEntry("Playback started", category: "playback", metadata: self.diagnosticMetadata))
            } catch is CancellationError { self.logger.trace("Playback audio session activation cancelled", category: "playback") }
            catch {
                guard self.generation == token else { return }
                self.logger.error("Playback audio session failed", error: error, category: "playback", metadata: self.diagnosticMetadata)
                self.error = error.localizedDescription; self.wantsPlayback = false; self.playing = false
            }
        }
    }

    func pause() {
        if playing || wantsPlayback { logger.debug("Playback pause requested", category: "playback", metadata: diagnosticMetadata) }
        wantsPlayback = false
        audio.pause(); playing = false; save(); updateNowPlaying()
    }

    func stop() {
        if book != nil || loading { logger.debug("Playback stop requested", category: "playback", metadata: diagnosticMetadata) }
        pause(); loadTask?.cancel(); generation = UUID(); cancelSleep()
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        completionObserver = nil
        audio.replaceCurrentItem(with: nil)
        book = nil; elapsed = 0; duration = 0; trackIndex = 0; artwork = nil; loading = false; error = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let previous = sessionTask
        sessionTask = Task { [logger] in
            await previous?.value
            do { _ = try await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) }
            catch is CancellationError { logger.trace("Playback audio session release cancelled", category: "playback") }
            catch { logger.warning("Playback audio session release failed", error: error, category: "playback") }
        }
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else {
            logger.warning("Playback seek rejected because the position is not finite", category: "playback", metadata: diagnosticMetadata)
            return
        }
        logger.trace("Playback seek requested", category: "playback", metadata: diagnosticMetadata.merging(["requested_seconds": .double(seconds)]) { _, new in new })
        elapsed = max(0, min(seconds, duration > 0 ? duration : max(0, seconds)))
        audio.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        save(); updateNowPlaying()
    }
    func skip(_ seconds: Double) { seek(elapsed + seconds) }
    func setSpeed(_ rate: Float) {
        speed = rate; if playing { audio.rate = rate }; updateNowPlaying()
        logger.debug("Playback speed changed", category: "playback", metadata: diagnosticMetadata)
    }

    func selectChapter(_ chapter: BookChapter) {
        logger.debug("Playback chapter selection requested", category: "playback", metadata: diagnosticMetadata)
        cancelSleep()
        guard let book else { return }
        if book.manifest.audio != nil, let start = chapter.startTime { load(index: 0, at: start, autoplay: true) }
        else if let index = tracks.firstIndex(where: { $0.chapterID == chapter.id }) { load(index: index, at: 0, autoplay: true) }
        else { logger.warning("Selected chapter has no playable recording", category: "playback", metadata: diagnosticMetadata) }
    }

    func setSleep(minutes: Int) {
        cancelSleep()
        sleepLabel = "\(minutes) min"
        logger.debug("Playback sleep timer started", category: "playback", metadata: diagnosticMetadata.merging(["sleep_minutes": .integer(minutes)]) { _, new in new })
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(minutes * 60)) }
            catch is CancellationError {
                self?.logger.trace("Playback sleep timer cancelled", category: "playback")
                return
            }
            catch {
                self?.logger.warning("Playback sleep timer failed", error: error, category: "playback")
                return
            }
            self?.logger.debug("Playback sleep timer reached its deadline", category: "playback")
            self?.pause(); self?.cancelSleep()
        }
    }
    func sleepAtChapterEnd() {
        cancelSleep()
        guard let book, canSleepAtChapterEnd else { return }
        sleepBoundary = book.manifest.audio == nil ? .infinity : AudioTrack.nextBoundary(after: elapsed, in: book.manifest, duration: duration)
        sleepLabel = String(localized: "End of chapter")
        logger.debug("Playback sleep at chapter end enabled", category: "playback", metadata: diagnosticMetadata)
    }
    func cancelSleep() {
        if sleepLabel != nil { logger.trace("Playback sleep setting cleared", category: "playback", metadata: diagnosticMetadata) }
        sleepTask?.cancel(); sleepTask = nil; sleepBoundary = nil; sleepLabel = nil
    }

    private func load(index: Int, at seconds: Double, autoplay: Bool) {
        guard let book, let repository, let root, tracks.indices.contains(index) else {
            logger.warning("Recording load cannot start because its playback context is unavailable", category: "playback", metadata: [
                "has_book": .bool(book != nil), "has_repository": .bool(repository != nil), "has_library_root": .bool(root != nil),
                "requested_track_index": .integer(index), "track_count": .integer(tracks.count)
            ])
            return
        }
        save(); audio.pause(); playing = false; loadTask?.cancel()
        let token = UUID(); generation = token
        wantsPlayback = autoplay; loading = true; error = nil; duration = 0; trackIndex = index; elapsed = max(0, seconds); lastSave = 0
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }; completionObserver = nil
        audio.replaceCurrentItem(with: nil)
        let track = tracks[index]
        logger.trace("Recording load started", category: "playback", metadata: diagnosticMetadata.merging(["autoplay": .bool(autoplay)]) { _, new in new })
        updateNowPlaying()
        loadTask = Task { [weak self] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            var phase = "asset_resolution"
            do {
                let url = try await repository.asset(track.path, book: book, root: root, operationID: token.uuidString)
                await repository.flushDiagnosticLogs()
                self?.logger.trace("Playback recording asset resolved", category: "playback", metadata: ["diagnostic_operation_id": .string(token.uuidString), "book_id": .string(book.id.uuidString), "track_index": .integer(index)])
                phase = "audio_validation"
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let length = try await asset.load(.duration).seconds
                self?.logger.debug("Playback recording format checked", category: "playback", metadata: ["diagnostic_operation_id": .string(token.uuidString),
                    "book_id": .string(book.id.uuidString), "track_index": .integer(index), "is_playable": .bool(playable), "duration_seconds": .double(length.isFinite ? length : 0)])
                guard playable, length.isFinite, length > 0 else { throw BookError.invalid("This recording cannot be played.") }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                phase = "chapter_timestamp_validation"
                let lastTimestamp = book.manifest.orderedChapters.compactMap(\.startTime).last ?? 0
                guard book.manifest.audio == nil || lastTimestamp < length else { throw BookError.invalid("Chapter timestamps exceed the recording duration.") }
                self.duration = length
                let item = AVPlayerItem(asset: asset)
                self.audio.replaceCurrentItem(with: item)
                self.completionObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard self?.generation == token else { return }
                        self?.completed()
                    }
                }
                let position = max(0, min(seconds, length))
                phase = "seek"
                let seekCompleted = await self.audio.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard self.generation == token, !Task.isCancelled else { return }
                self.elapsed = position; self.loading = false
                if !seekCompleted { self.logger.warning("Playback initial seek was interrupted", category: "playback", metadata: self.diagnosticMetadata) }
                self.logger.debug("Recording loaded", category: "playback", metadata: self.diagnosticMetadata.merging(["duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)]) { _, new in new })
                if self.wantsPlayback { self.resume() }
                self.save(); self.updateNowPlaying()
                if let cover = book.manifest.cover {
                    do {
                        let imageURL = try await repository.asset(cover, book: book, root: root, operationID: token.uuidString)
                        let data = try await repository.imageData(imageURL)
                        await repository.flushDiagnosticLogs()
                        let decoded = await ArtworkDecoder.thumbnail(data)
                        guard self.generation == token, !Task.isCancelled else { return }
                        if let decoded {
                            let image = UIImage(cgImage: decoded)
                            // MediaPlayer requests artwork on background queues. A Sendable
                            // callback must not inherit StoryPlayer's MainActor isolation.
                            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
                            self.updateNowPlaying()
                        } else { self.logger.warning("Playback artwork could not be decoded", category: "playback") }
                    } catch is CancellationError { self.logger.trace("Playback artwork loading cancelled", category: "playback") }
                    catch {
                        let snapshot = ErrorSnapshot(error)
                        await repository.flushDiagnosticLogs()
                        guard self.generation == token else { return }
                        self.logger.log(LogEntry("Playback artwork unavailable", level: .warning, category: "playback", metadata: self.diagnosticMetadata, error: snapshot))
                    }
                }
            } catch is CancellationError {
                await repository.flushDiagnosticLogs()
                self?.logger.trace("Recording load cancelled", category: "playback", metadata: ["book_id": .string(book.id.uuidString), "track_index": .integer(index), "diagnostic_operation_id": .string(token.uuidString), "phase": .string(phase)])
            }
            catch {
                let snapshot = ErrorSnapshot(error)
                await repository.flushDiagnosticLogs()
                guard let self, self.generation == token else { return }
                self.logger.log(LogEntry("Recording load failed", level: .error, category: "playback", metadata: self.diagnosticMetadata.merging(["phase": .string(phase), "duration_ms": .double(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)]) { _, new in new }, error: snapshot))
                self.loading = false; self.playing = false; self.wantsPlayback = false; self.error = error.localizedDescription; self.updateNowPlaying()
            }
        }
    }

    private func tick() {
        guard book != nil, !loading, audio.currentItem != nil else { return }
        let time = audio.currentTime().seconds
        if time.isFinite { elapsed = max(0, time) }
        if let boundary = sleepBoundary, boundary.isFinite, elapsed >= boundary { pause(); cancelSleep() }
        if audio.currentItem?.status == .failed {
            if let failure = audio.currentItem?.error {
                logger.error("Playback recording decoder failed", error: failure, category: "playback", metadata: diagnosticMetadata)
            } else {
                logger.error("Playback recording decoder failed without an SDK error", category: "playback", metadata: diagnosticMetadata)
            }
            error = audio.currentItem?.error?.localizedDescription ?? String(localized: "Playback failed. Try again.")
            pause(); audio.replaceCurrentItem(with: nil)
        }
        if abs(elapsed - lastSave) >= 5 { save(); lastSave = elapsed; updateNowPlaying() }
    }

    private func completed() {
        logger.debug("Playback recording reached its end", category: "playback", metadata: diagnosticMetadata)
        elapsed = duration; save()
        if sleepBoundary != nil { pause(); cancelSleep(); return }
        if trackIndex + 1 < tracks.count { load(index: trackIndex + 1, at: 0, autoplay: wantsPlayback) }
        else { pause() }
    }
    private func save() {
        guard let book else { return }
        progress?.save(PlaybackPosition(bookID: book.id, chapterID: tracks[safe: trackIndex]?.chapterID, seconds: elapsed))
    }
    private func resetEngine() {
        loadTask?.cancel(); generation = UUID(); loading = false
        if let timeObserver { audio.removeTimeObserver(timeObserver) }
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        completionObserver = nil
        audio = AVPlayer()
        timeObserver = audio.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    private func updateNowPlaying() {
        guard let book else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: book.manifest.title, MPMediaItemPropertyAlbumTitle: chapterTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed, MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0, MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if let author = book.manifest.author { info[MPMediaItemPropertyArtist] = author }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Remote commands also arrive off the main actor; only the player action hops back.
        commandTargets.append((center.playCommand, center.playCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.resume() }; return .success }))
        commandTargets.append((center.pauseCommand, center.pauseCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.pause() }; return .success }))
        commandTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }))
        center.skipForwardCommand.preferredIntervals = [15]; center.skipBackwardCommand.preferredIntervals = [15]
        commandTargets.append((center.skipForwardCommand, center.skipForwardCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.skip(15) }; return .success }))
        commandTargets.append((center.skipBackwardCommand, center.skipBackwardCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.skip(-15) }; return .success }))
        commandTargets.append((center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(position) }; return .success
        }))
    }
    isolated deinit {
        loadTask?.cancel(); sleepTask?.cancel()
        if let timeObserver { audio.removeTimeObserver(timeObserver) }
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        for observer in interruptions { NotificationCenter.default.removeObserver(observer) }
        for (command, target) in commandTargets { command.removeTarget(target) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
