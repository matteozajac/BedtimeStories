import AVFoundation
import CryptoKit
import Foundation
import MZAppFoundation

/// Enrollment audio is private scratch data, separate from books and iCloud.
actor VoiceEnrollmentAudio {
    static let shared = VoiceEnrollmentAudio()

    func prepare(_ source: URL, userID: String, consent: Bool) async throws -> URL {
        let operation = CloudNarrationLogOperation(name: "prepare_enrollment_recording")
        await AppLog.trace("Enrollment audio preparation started", category: "cloud_narration", metadata: operation.metadata.merging(["recording_kind": .string(consent ? "consent" : "reference")]) { _, new in new })
        do {
            let url = try convert(source, userID: userID, consent: consent)
            await AppLog.debug("Enrollment audio preparation completed", category: "cloud_narration", metadata: operation.metadata)
            return url
        } catch {
            let snapshot = ErrorSnapshot(error)
            if ErrorSnapshot.isCancellation(error) {
                await AppLog.trace("Enrollment audio preparation cancelled", category: "cloud_narration", metadata: operation.metadata)
                throw error
            }
            await MainActor.run {
                AppLog.logger.log(LogEntry("Enrollment audio preparation failed", level: .error, category: "cloud_narration", metadata: operation.metadata, error: snapshot, source: snapshot.source))
            }
            if let error = error as? BookError { throw error }
            throw BookError.invalid(String(localized: "This recording could not be prepared. Record another take."))
        }
    }

    private func convert(_ source: URL, userID: String, consent: Bool) throws -> URL {
        try Task.checkCancellation()
        let input = try AVAudioFile(forReading: source)
        let duration = Double(input.length) / input.processingFormat.sampleRate
        guard duration.isFinite, duration >= (consent ? 2 : 10), duration <= 30,
              input.processingFormat.channelCount <= 2 else {
            throw BookError.invalid(consent
                ? String(localized: "Record the complete consent statement in 2–30 seconds.")
                : String(localized: "Record 10–30 seconds of clear speech in a quiet room."))
        }
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)),
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(duration * 24_000) + 64)) else {
            throw BookError.invalid(String(localized: "This recording could not be prepared. Record another take."))
        }
        try input.read(into: sourceBuffer)
        var supplied = false
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData
            return sourceBuffer
        }
        if let error { throw error }
        guard result != .error, output.frameLength > 0, let samples = output.int16ChannelData?[0] else {
            throw BookError.invalid(String(localized: "This recording could not be prepared. Record another take."))
        }
        try Task.checkCancellation()
        let sampleBytes = Int(output.frameLength) * 2
        guard sampleBytes <= 1_440_000 else { throw BookError.invalid(String(localized: "The recording is too long. Record a shorter take.")) }
        var wav = Data()
        func put(_ number: UInt32, bytes: Int = 4) {
            for index in 0..<bytes { wav.append(UInt8((number >> (index * 8)) & 255)) }
        }
        wav.append(Data("RIFF".utf8)); put(UInt32(sampleBytes + 36)); wav.append(Data("WAVEfmt ".utf8))
        put(16); put(1, bytes: 2); put(1, bytes: 2); put(24_000); put(48_000); put(2, bytes: 2); put(16, bytes: 2)
        wav.append(Data("data".utf8)); put(UInt32(sampleBytes))
        wav.append(Data(buffer: UnsafeBufferPointer(start: samples, count: Int(output.frameLength))))
        let namespace = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        var directory = URL.cachesDirectory.appendingPathComponent("CloudVoiceEnrollment/\(namespace)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let destination = directory.appendingPathComponent("\(consent ? "Consent" : "Reference")-\(UUID().uuidString).wav")
        try wav.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    func remove(_ urls: [URL]) async {
        let operation = CloudNarrationLogOperation(name: "remove_enrollment_recordings")
        for url in urls {
            do { try FileManager.default.removeItem(at: url) }
            catch {
                let nsError = error as NSError
                guard nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileNoSuchFileError else { continue }
                let snapshot = ErrorSnapshot(error)
                await MainActor.run {
                    AppLog.logger.log(LogEntry("Enrollment recording cleanup failed", level: .warning, category: "cloud_narration", metadata: operation.metadata, error: snapshot, source: snapshot.source))
                }
            }
        }
        await AppLog.trace("Enrollment recording cleanup completed", category: "cloud_narration", metadata: operation.metadata.merging(["recording_count": .integer(urls.count)]) { _, new in new })
    }
}
