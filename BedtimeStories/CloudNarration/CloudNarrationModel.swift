import AuthenticationServices
import CryptoKit
@preconcurrency import FirebaseAppCheck
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions
@preconcurrency import FirebaseStorage
import Foundation
import MZAppFoundation
import Observation
import Security

@Observable @MainActor
final class CloudNarrationModel {
    private(set) var isConfigured = false
    private(set) var isEnabled = false
    private(set) var userID: String?
    private(set) var isWorking = false
    var message: String?
    private(set) var voices: [VoiceProfile] = []
    private(set) var jobs: [NarrationJob] = []
    @ObservationIgnored private var auth: Auth?
    @ObservationIgnored private var database: Firestore?
    @ObservationIgnored private var functions: Functions?
    @ObservationIgnored private var storage: Storage?
    @ObservationIgnored private var authListener: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var voiceListener: (any ListenerRegistration)?
    @ObservationIgnored private var jobListener: (any ListenerRegistration)?
    @ObservationIgnored private var nonce: String?
    @ObservationIgnored private var appleAuthorizationCode: String?
    @ObservationIgnored private var accountGeneration = UUID()
    @ObservationIgnored private var downloads: [UUID: StorageDownloadTask] = [:]
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var signInAttempt = UUID()
    @ObservationIgnored private var acceptsAuthChanges = true
    @ObservationIgnored private let logger: any AppLogging

    init(configureFirebase: Bool = true, logger: any AppLogging = AppLog.logger) {
        self.logger = logger
        guard configureFirebase,
              (Bundle.main.object(forInfoDictionaryKey: "CloudNarrationEnabled") as? NSString)?.boolValue == true,
              RuntimeSafety.permitsRemote(environment: MZBootstrap.services.configuration.environment),
              let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let options = FirebaseOptions(contentsOfFile: url.path),
              options.projectID == "gen-lang-client-0154884984",
              options.googleAppID == "1:280562253820:ios:eed3a08d4e7e6a6b677c79",
              options.bundleID == Bundle.main.bundleIdentifier else { return }
        if FirebaseApp.app() == nil {
            AppCheck.setAppCheckProviderFactory(CloudAppCheckProviderFactory())
            FirebaseApp.configure(options: options)
        }
        isConfigured = true
        isEnabled = true
        auth = Auth.auth()
        let database = Firestore.firestore()
        let settings = database.settings
        settings.cacheSettings = MemoryCacheSettings()
        database.settings = settings
        self.database = database
        functions = Functions.functions(region: "europe-west1")
        if let bucket = Bundle.main.object(forInfoDictionaryKey: "CloudNarrationOutputBucket") as? String, !bucket.isEmpty {
            storage = Storage.storage(url: "gs://" + bucket)
        } else {
            storage = Storage.storage()
        }
        authListener = auth?.addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            Task { @MainActor [weak self] in self?.changedAccount(to: uid) }
        }
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        guard isConfigured, isEnabled else { message = CloudNarrationFailure.unavailable.localizedDescription; return }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            message = String(localized: "Sign-in could not start. Try again."); return
        }
        let nonce = bytes.map { String(format: "%02x", $0) }.joined()
        self.nonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        let pendingNonce = nonce
        nonce = nil
        guard let auth, isEnabled else { message = CloudNarrationFailure.unavailable.localizedDescription; return }
        do {
            let authorization = try result.get()
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken,
                  let token = String(data: tokenData, encoding: .utf8), let pendingNonce else {
                throw CloudNarrationFailure.invalidResponse
            }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: pendingNonce, fullName: apple.fullName)
            let authorizationCode = apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let previousTask = signInTask
            previousTask?.cancel()
            let attempt = UUID()
            signInAttempt = attempt
            acceptsAuthChanges = false
            isWorking = true
            signInTask = Task { [weak self] in
                // Firebase authentication may finish after cancellation. Serialize attempts so an old
                // result is signed out before a newer attempt can establish another account.
                await previousTask?.value
                guard let self, self.signInAttempt == attempt, !Task.isCancelled else { return }
                self.acceptsAuthChanges = true
                defer { if self.signInAttempt == attempt { self.isWorking = false } }
                do {
                    if let current = auth.currentUser {
                        _ = try await current.reauthenticate(with: credential)
                    } else {
                        _ = try await auth.signIn(with: credential)
                    }
                    if Task.isCancelled { try? auth.signOut(); return }
                    guard self.signInAttempt == attempt else { try? auth.signOut(); return }
                    self.appleAuthorizationCode = authorizationCode
                    self.changedAccount(to: auth.currentUser?.uid)
                    self.message = nil
                } catch {
                    if self.signInAttempt == attempt, !Task.isCancelled {
                        self.logger.error("Cloud sign-in failed", error: error, category: "cloud_narration")
                        self.message = String(localized: "Sign-in could not finish. Try again.")
                    }
                }
            }
        } catch {
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                logger.error("Apple sign-in failed", error: error, category: "cloud_narration")
                message = String(localized: "Sign-in could not finish. Try again.")
            }
        }
    }

    func signOut() {
        signInAttempt = UUID()
        acceptsAuthChanges = false
        signInTask?.cancel()
        isWorking = false
        do { try auth?.signOut(); changedAccount(to: nil) }
        catch {
            logger.error("Cloud sign-out failed", error: error, category: "cloud_narration")
            message = String(localized: "Sign-out could not finish. Try again.")
        }
    }

    func beginEnrollment(name: String, language: String, retentionAccepted: Bool) async throws -> VoiceEnrollment {
        guard retentionAccepted else { throw CloudNarrationFailure.invalidRecording }
        let data = try await call("beginVoiceEnrollment", payload: ["displayName": name, "language": language,
                        "consentVersion": "2026-10-01", "retentionAccepted": retentionAccepted])
        return try decode(VoiceEnrollment.self, data: data)
    }

    func uploadEnrollment(enrollment: VoiceEnrollment, referenceURL: URL, consentURL: URL) async throws -> String {
        let session = try currentSession()
        guard enrollment.expiresAt > Date().timeIntervalSince1970 else { throw CloudNarrationFailure.expired }
        for (kind, url) in [("reference", referenceURL), ("consent", consentURL)] {
            let data: Data
            do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
            catch {
                logger.error("Enrollment recording read failed", error: error, category: "cloud_narration")
                throw CloudNarrationFailure.invalidRecording
            }
            guard data.count <= 1_500_000 else { throw CloudNarrationFailure.invalidAudio }
            try validate(session)
            _ = try await call("uploadEnrollmentRecording", payload: ["enrollmentId": enrollment.enrollmentId,
                              "kind": kind, "audioBase64": data.base64EncodedString()])
            try validate(session)
        }
        let response = try await call("completeVoiceEnrollment", payload: ["enrollmentId": enrollment.enrollmentId])
        try validate(session)
        guard let id = response["profileId"] as? String else { throw CloudNarrationFailure.invalidResponse }
        return id
    }

    func approveVoice(profileID: String) async throws {
        _ = try await call("approveVoice", payload: ["profileId": profileID])
    }

    func startVoicePreview(profileID: String) async throws -> String {
        guard let voice = voices.first(where: { $0.id == profileID }) else { throw CloudNarrationFailure.staleVoice }
        let text = voice.language == "pl-PL"
            ? "Mały lis otulił się ciepłym kocem. Za oknem gwiazdy migotały na niebie. Jesteś bezpieczny, szepnęła mama. Jutro czeka nas nowa przygoda."
            : "The little fox curled up beneath a warm blanket. Outside, the stars sparkled in the sky. You are safe, whispered Mum. Tomorrow brings a new adventure."
        var draft = BookDraft()
        draft.title = String(localized: "Voice Preview")
        draft.chapters = [DraftChapter(title: "", text: text)]
        return try await startNarration(draft: draft, voiceID: profileID, styles: [:], defaultStyle: .gentle, preview: true)
    }

    func startNarration(draft: BookDraft, voiceID: String, styles: [UUID: [NarrationStyle]],
                        defaultStyle: NarrationStyle, preview: Bool) async throws -> String {
        let session = try currentSession()
        guard let voice = voices.first(where: { $0.id == voiceID }),
              voice.status == "ready" || (preview && voice.status == "awaitingApproval") else {
            throw CloudNarrationFailure.staleVoice
        }
        let snapshot = NarrationSnapshot(draft: draft, styles: styles, defaultStyle: defaultStyle)
        let hash = try snapshot.hash
        var chapters = snapshot.chapters.filter { !$0.paragraphs.isEmpty }
        if preview, let first = chapters.first {
            let text = first.paragraphs.first?.text ?? ""
            let short = String(text.prefix(500))
            chapters = [.init(id: first.id, title: first.title, sourceText: short,
                              paragraphs: [.init(text: short, style: first.paragraphs.first?.style ?? defaultStyle)])]
        }
        let wireChapters: [[String: Any]] = chapters.map { chapter in
            ["id": chapter.id, "title": chapter.title, "paragraphs": chapter.paragraphs.map {
                ["text": $0.text, "style": $0.style.rawValue]
            }]
        }
        let requestID: String
        do {
            requestID = try NarrationRequestReceipt.requestID(uid: session.uid, draftID: draft.id,
                                                            snapshotHash: hash, voiceID: voiceID, preview: preview)
        } catch {
            logger.error("Narration request receipt failed", error: error, category: "cloud_narration")
            throw CloudNarrationFailure.retryLater
        }
        let response = try await call("startNarration", payload: ["requestId": requestID,
                   "voiceProfileId": voiceID, "draftId": draft.id.uuidString, "snapshotHash": hash,
                   "language": voice.language, "preview": preview, "chapters": wireChapters])
        try validate(session)
        guard let id = response["jobId"] as? String else { throw CloudNarrationFailure.invalidResponse }
        NarrationRequestReceipt.confirm(uid: session.uid, requestID: requestID)
        return id
    }

    func snapshotHash(draft: BookDraft, styles: [UUID: [NarrationStyle]], defaultStyle: NarrationStyle) -> String {
        (try? NarrationSnapshot(draft: draft, styles: styles, defaultStyle: defaultStyle).hash) ?? ""
    }

    func cancel(jobID: String) async throws { _ = try await call("cancelNarration", payload: ["jobId": jobID]) }
    func deleteVoice(profileID: String) async throws { _ = try await call("deleteVoice", payload: ["profileId": profileID]) }

    func deleteAccount() async throws {
        guard let auth, let code = appleAuthorizationCode else {
            message = String(localized: "Confirm with Apple before deleting your voice account.")
            throw CloudNarrationFailure.signInRequired
        }
        // Apple's authorization is separate from deleting our private cloud data.
        let session = try currentSession()
        do { try await auth.revokeToken(withAuthorizationCode: code) }
        catch {
            logger.error("Apple account revocation failed", error: error, category: "cloud_narration")
            throw CloudNarrationFailure.confirmWithApple
        }
        try validate(session)
        appleAuthorizationCode = nil
        _ = try await call("deleteAccount", payload: [:])
        signOut()
    }

    func download(job: NarrationJob) async throws -> [UUID: URL] {
        let session = try currentSession()
        guard job.state == "ready", jobs.contains(where: { $0.id == job.id && $0 == job }),
              job.expiresAt > Date().timeIntervalSince1970, !job.outputs.isEmpty, let storage else {
            throw CloudNarrationFailure.expired
        }
        let directory: URL
        do {
            directory = try privateCache(for: session.uid).appendingPathComponent(job.id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Narration cache preparation failed", error: error, category: "cloud_narration")
            throw CloudNarrationFailure.retryLater
        }
        var results: [UUID: URL] = [:]
        do {
            for output in job.outputs {
                try validate(session)
                guard let chapterID = UUID(uuidString: output.chapterId),
                      output.path == "users/\(session.uid)/jobs/\(job.id)/\(output.chapterId).m4a",
                      output.bytes > 0, output.bytes <= 100_000_000, output.duration > 0,
                      results[chapterID] == nil else { throw CloudNarrationFailure.invalidAudio }
                let url = directory.appendingPathComponent(chapterID.uuidString + ".m4a")
                try await download(storage.reference(withPath: output.path), to: url, session: session)
                try validate(session)
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count == output.bytes,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == output.sha256 else {
                    throw CloudNarrationFailure.invalidAudio
                }
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
                results[chapterID] = url
            }
            try validate(session)
            return results
        } catch {
            try? FileManager.default.removeItem(at: directory)
            try validate(session)
            if error is CancellationError { throw error }
            logger.error("Narration download failed", error: error, category: "cloud_narration")
            if let failure = error as? CloudNarrationFailure { throw failure }
            throw CloudNarrationFailure.retryLater
        }
    }

    private struct Session { let uid: String; let generation: UUID }
    private func currentSession() throws -> Session {
        guard isConfigured, isEnabled else { throw CloudNarrationFailure.unavailable }
        guard let uid = userID, auth?.currentUser?.uid == uid else { throw CloudNarrationFailure.signInRequired }
        return Session(uid: uid, generation: accountGeneration)
    }
    private func validate(_ session: Session) throws {
        guard session.uid == userID, session.generation == accountGeneration,
              auth?.currentUser?.uid == session.uid else { throw CloudNarrationFailure.accountChanged }
        try Task.checkCancellation()
    }

    private func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let session = try currentSession()
        guard let functions else { throw CloudNarrationFailure.unavailable }
        let callable = functions.httpsCallable(name, options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true))
        callable.timeoutInterval = 90
        let result: HTTPSCallableResult
        do {
            // Reconstitute a disconnected JSON value before transferring it to the SDK's concurrent API.
            let json = try JSONSerialization.data(withJSONObject: payload)
            result = try await callable.call(JSONSerialization.jsonObject(with: json))
        }
        catch {
            try validate(session)
            logger.error("Cloud narration request failed", error: error, category: "cloud_narration", metadata: ["operation": .string(name)])
            let code = (error as NSError).code
            switch FunctionsErrorCode(rawValue: code) {
            case .unauthenticated: throw CloudNarrationFailure.signInRequired
            case .permissionDenied: throw CloudNarrationFailure.permissionDenied
            case .resourceExhausted: throw CloudNarrationFailure.limitReached
            case .invalidArgument: throw CloudNarrationFailure.invalidRecording
            case .failedPrecondition:
                if name == "deleteVoice" || name == "deleteAccount" { throw CloudNarrationFailure.confirmWithApple }
                throw CloudNarrationFailure.unavailable
            default: throw CloudNarrationFailure.retryLater
            }
        }
        try validate(session)
        guard let data = result.data as? [String: Any] else { throw CloudNarrationFailure.invalidResponse }
        return data
    }

    private func changedAccount(to uid: String?) {
        guard uid == auth?.currentUser?.uid else { return }
        if uid != nil, !acceptsAuthChanges { try? auth?.signOut(); return }
        guard userID != uid else { return }
        accountGeneration = UUID()
        voiceListener?.remove(); jobListener?.remove()
        voiceListener = nil; jobListener = nil
        for task in downloads.values { task.cancel() }
        downloads.removeAll()
        voices = []; jobs = []; message = nil
        let oldUID = userID
        userID = uid
        if let oldUID {
            appleAuthorizationCode = nil
            NarrationDraftPreferences.removePrivateData(userID: oldUID)
            NarrationRequestReceipt.removePrivateData(uid: oldUID)
            if let cache = try? privateCache(for: oldUID) { try? FileManager.default.removeItem(at: cache) }
        }
        guard let uid, let database, isEnabled else { return }
        let generation = accountGeneration
        voiceListener = database.collection("users/\(uid)/voices").addSnapshotListener { [weak self] snapshot, error in
            let profiles = snapshot?.documents.compactMap { doc -> VoiceProfile? in
                var data = doc.data(); data["id"] = doc.documentID
                return try? Self.decodeDocument(VoiceProfile.self, data: data)
            } ?? []
            let failure = error.map { ErrorSnapshot($0) }
            Task { @MainActor [weak self] in
                guard let self, self.userID == uid, self.accountGeneration == generation else { return }
                if let failure {
                    self.logger.log(LogEntry("Voice profiles load failed", level: .error, category: "cloud_narration", error: failure))
                    self.voices = []; self.message = String(localized: "Your voices could not be loaded. Try again.")
                }
                else { self.voices = profiles.sorted { $0.createdAt > $1.createdAt } }
            }
        }
        jobListener = database.collection("users/\(uid)/jobs").addSnapshotListener { [weak self] snapshot, error in
            let jobs = snapshot?.documents.compactMap { doc -> NarrationJob? in
                var data = doc.data(); data["id"] = doc.documentID
                return try? Self.decodeDocument(NarrationJob.self, data: data)
            } ?? []
            let failure = error.map { ErrorSnapshot($0) }
            Task { @MainActor [weak self] in
                guard let self, self.userID == uid, self.accountGeneration == generation else { return }
                if let failure {
                    self.logger.log(LogEntry("Narration jobs load failed", level: .error, category: "cloud_narration", error: failure))
                    self.jobs = []; self.message = String(localized: "Your narrations could not be loaded. Try again.")
                }
                else {
                    self.jobs = jobs.sorted { $0.createdAt > $1.createdAt }
                    NarrationRequestReceipt.confirm(uid: uid, requestIDs: Set(jobs.map(\.id)))
                }
            }
        }
    }

    nonisolated private static func decodeDocument<T: Decodable>(_ type: T.Type, data: [String: Any]) throws -> T {
        func normalize(_ value: Any) -> Any {
            if let timestamp = value as? Timestamp { return timestamp.dateValue().timeIntervalSince1970 }
            if let dict = value as? [String: Any] { return dict.mapValues(normalize) }
            if let array = value as? [Any] { return array.map(normalize) }
            return value
        }
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: normalize(data)))
    }
    private func decode<T: Decodable>(_ type: T.Type, data: [String: Any]) throws -> T {
        do { return try Self.decodeDocument(type, data: data) }
        catch {
            logger.error("Cloud narration response decoding failed", error: error, category: "cloud_narration")
            throw CloudNarrationFailure.invalidResponse
        }
    }

    private func privateCache(for uid: String) throws -> URL {
        let root = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let name = SHA256.hash(data: Data(uid.utf8)).map { String(format: "%02x", $0) }.joined()
        var directory = root.appendingPathComponent("PrivateNarration/" + name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    private func download(_ reference: StorageReference, to url: URL, session: Session) async throws {
        let id = UUID()
        defer { downloads[id] = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = reference.write(toFile: url) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
                downloads[id] = task
                if Task.isCancelled { task.cancel() }
            }
            try validate(session)
        } onCancel: {
            Task { @MainActor [weak self] in self?.downloads[id]?.cancel() }
        }
    }
}
