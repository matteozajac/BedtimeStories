import AVFoundation
import Foundation
import MZAppFoundation
import Observation

@Observable @MainActor
final class NarrationRecorder: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private(set) var preparing = false
    private(set) var recording = false
    private(set) var paused = false
    private(set) var finishing = false
    private(set) var playing = false
    private(set) var ready = false
    private(set) var elapsed = 0.0
    private(set) var level = 0.0
    private(set) var url: URL?
    private(set) var permissionDenied = false
    var message: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var preview: AVAudioPlayer?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var sessionRelease: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var recordingFailed = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger: any AppLogging

    init(logger: any AppLogging = AppLog.logger) {
        self.logger = logger
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] note in
            let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            guard context?.interruptionContext != nil else { return }
            Task { @MainActor [weak self] in self?.pauseForInterruption() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pauseForInterruption() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logger.warning("Recording audio services reset", category: "recording")
                self?.cancel()
                self?.message = String(localized: "Audio was interrupted. Start a new take when you’re ready.")
            }
        })
    }

    var busy: Bool { preparing || finishing }
    var hasTake: Bool { url != nil }

    func start() {
        guard !busy, !recording else { return }
        resetTake()
        preparing = true; message = nil; permissionDenied = false
        logger.trace("Microphone permission requested", category: "recording")
        let token = generation
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled, self.generation == token else { return }
            guard allowed else {
                self.logger.log(LogEntry("Microphone permission denied", level: .notice, category: "recording"))
                self.preparing = false; self.permissionDenied = true
                self.message = String(localized: "Allow microphone access in Settings to record your narration. You can still write your book or import audio.")
                return
            }
            await self.activateRecording(token: token, resuming: false)
        }
    }

    func pause() {
        guard recording else { return }
        recorder?.pause(); recording = false; paused = true
        logger.log(LogEntry("Recording paused", level: .debug, category: "recording"))
        meter?.cancel(); level = 0
        releaseSession()
    }

    func resume() {
        guard paused, !busy else { return }
        preparing = true; message = nil
        logger.trace("Recording resume requested", category: "recording")
        let token = generation
        let previous = operation
        operation = Task { [weak self] in await previous?.value; await self?.activateRecording(token: token, resuming: true) }
    }

    func finish() {
        guard (recording || paused), !busy else { return }
        meter?.cancel(); recording = false; paused = false; finishing = true; level = 0
        logger.trace("Recording completion requested", category: "recording")
        recorder?.stop()
        releaseSession()
        // An interruption can suppress the recorder delegate callback. Explicit
        // completion also checks the closed file so the review never stays busy.
        if let file = url {
            let previous = operation
            operation = Task { [weak self] in await previous?.value; await self?.complete(file: file, successfully: true) }
        }
    }

    func togglePreview() {
        if playing { preview?.stop(); playing = false; releaseSession(); return }
        guard ready, let url, !busy else { return }
        preparing = true
        let token = generation
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.sessionRelease?.value
            guard self.generation == token, !Task.isCancelled else { return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                let activated = try await session.activate(options: [])
                guard self.generation == token, !Task.isCancelled else { self.releaseSession(); return }
                guard activated else { throw BookError.unavailable("Audio is unavailable.") }
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                guard player.play() else { throw BookError.unavailable("Audio is unavailable.") }
                self.preview = player; self.playing = true
                self.logger.log(LogEntry("Recording preview started", level: .debug, category: "recording"))
            } catch is CancellationError {
                self.logger.trace("Recording preview cancelled", category: "recording")
                self.releaseSession()
            }
            catch {
                self.logger.error("Recording preview failed", error: error, category: "recording")
                self.message = String(localized: "The take could not be played. Try again."); self.releaseSession()
            }
            self.preparing = false
        }
    }

    func pauseForInterruption() {
        logger.trace("Recording audio interruption received", category: "recording", metadata: ["preparing": .bool(preparing), "recording": .bool(recording), "previewing": .bool(playing)])
        if preparing {
            generation = UUID(); operation?.cancel(); preparing = false
            releaseSession()
        }
        if recording { pause(); message = String(localized: "Recording paused. Tap Resume when you’re ready.") }
        if playing { preview?.stop(); playing = false }
    }

    func cancel() {
        resetTake()
        releaseSession()
    }

    private func activateRecording(token: UUID, resuming: Bool) async {
        await sessionRelease?.value
        guard generation == token, !Task.isCancelled else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            let activated = try await session.activate(options: [])
            guard generation == token, !Task.isCancelled else { releaseSession(); return }
            guard activated else { throw BookError.unavailable("Audio is unavailable.") }
            if !resuming {
                let file = URL.temporaryDirectory.appendingPathComponent("StoryTake-\(UUID().uuidString).m4a")
                url = file
                let audio = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 128_000, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
                audio.delegate = self; audio.isMeteringEnabled = true
                recorder = audio
            }
            guard recorder?.record() == true else { throw BookError.unavailable("The microphone is unavailable.") }
            recording = true; paused = false; preparing = false
            logger.log(LogEntry("Microphone recording started", level: .debug, category: "recording", metadata: ["resuming": .bool(resuming)]))
            meter = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.recording, let audio = self.recorder else { return }
                    audio.updateMeters()
                    self.elapsed = audio.currentTime
                    self.level = max(0, min(1, pow(10, Double(audio.averagePower(forChannel: 0)) / 20)))
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
        } catch is CancellationError {
            logger.trace("Microphone session cancelled", category: "recording")
            preparing = false
            releaseSession()
        }
        catch {
            logger.error("Microphone session failed", error: error, category: "recording")
            preparing = false
            message = String(localized: "The microphone could not start. Close other recording apps, then try again. Your saved narration is unchanged.")
            releaseSession()
        }
    }

    private func resetTake() {
        generation = UUID()
        operation?.cancel(); meter?.cancel()
        recorder?.delegate = nil; recorder?.stop(); recorder = nil
        preview?.stop(); preview = nil
        removeTakeIfPresent()
        url = nil; recording = false; paused = false; finishing = false; preparing = false
        playing = false; ready = false; elapsed = 0; level = 0
        recordingFailed = false
    }

    private func releaseSession() {
        let previous = sessionRelease
        sessionRelease = Task { [logger] in
            await previous?.value
            do { _ = try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) }
            catch is CancellationError { logger.trace("Recording audio session release cancelled", category: "recording") }
            catch { logger.warning("Recording audio session release failed", error: error, category: "recording") }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let file = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.url == file else { return }
            if !flag { self.recordingFailed = true }
            await self.complete(file: file, successfully: flag)
        }
    }

    private func complete(file: URL, successfully: Bool) async {
        guard url == file, finishing || recording || paused else { return }
        recording = false; paused = false; meter?.cancel()
        let duration: Double
        do { duration = try await AVURLAsset(url: file).load(.duration).seconds }
        catch {
            guard url == file else { return }
            finishing = false; preparing = false; ready = false
            if ErrorSnapshot.isCancellation(error) { logger.trace("Recording validation cancelled", category: "recording") }
            else {
                logger.error("Recording duration validation failed", error: error, category: "recording")
                message = String(localized: "The take could not be finished. Try recording again.")
            }
            return
        }
        guard url == file else { return }
        finishing = false; preparing = false
        if successfully, !recordingFailed, duration.isFinite, duration > 0 {
            elapsed = duration; ready = true
            logger.log(LogEntry("Recording validated", level: .debug, category: "recording"))
        } else {
            logger.log(LogEntry("Recording did not complete", level: .warning, category: "recording"))
            ready = false; message = String(localized: "The take could not be finished. Try recording again.")
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let file = recorder.url
        let snapshot = error.map { ErrorSnapshot($0) }
        Task { @MainActor [weak self] in
            guard let self, self.url == file else { return }
            self.logger.log(LogEntry("Recording encoding failed", level: .error, category: "recording", error: snapshot))
            self.cancel(); self.message = String(localized: "The take could not be finished. Try recording again.")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.preview.map(ObjectIdentifier.init) == id else { return }
            if !flag { self.logger.warning("Recording preview did not finish successfully", category: "recording") }
            self.playing = false; self.releaseSession()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        let snapshot = error.map { ErrorSnapshot($0) }
        Task { @MainActor [weak self] in
            guard let self, self.preview.map(ObjectIdentifier.init) == id else { return }
            self.logger.log(LogEntry("Recording preview decoding failed", level: .error, category: "recording", error: snapshot))
            self.preview?.stop(); self.playing = false; self.releaseSession()
            self.message = String(localized: "The take could not be played. Try again.")
        }
    }

    private func removeTakeIfPresent() {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { logger.warning("Temporary recording cleanup failed", error: error, category: "recording") }
    }

    isolated deinit {
        operation?.cancel(); meter?.cancel()
        recorder?.delegate = nil; recorder?.stop(); preview?.stop()
        removeTakeIfPresent()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
