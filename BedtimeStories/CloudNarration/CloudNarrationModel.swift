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
    @ObservationIgnored private var observedVoiceStates: [String: String] = [:]
    @ObservationIgnored private var observedJobStates: [String: String] = [:]
    @ObservationIgnored private var observedVoiceFailureCodes: [String: String] = [:]
    @ObservationIgnored private var observedJobFailureCodes: [String: String] = [:]
    @ObservationIgnored private let logger: any AppLogging

    init(configureFirebase: Bool = true, logger: any AppLogging = AppLog.logger) {
        self.logger = logger
        logger.trace("Cloud narration configuration started", category: "cloud_narration")
        guard configureFirebase else {
            logger.trace("Cloud narration configuration skipped", category: "cloud_narration", metadata: ["reason": .string("injected_configuration")])
            return
        }
        guard (Bundle.main.object(forInfoDictionaryKey: "CloudNarrationEnabled") as? NSString)?.boolValue == true else {
            logger.trace("Cloud narration configuration skipped", category: "cloud_narration", metadata: ["reason": .string("feature_disabled")])
            return
        }
        guard RuntimeSafety.permitsRemote(environment: MZBootstrap.services.configuration.environment) else {
            logger.trace("Cloud narration configuration skipped", category: "cloud_narration", metadata: ["reason": .string("remote_services_disabled")])
            return
        }
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let options = FirebaseOptions(contentsOfFile: url.path) else {
            logger.error("Cloud narration configuration missing", category: "cloud_narration")
            return
        }
        guard options.projectID == "gen-lang-client-0154884984",
              options.googleAppID == "1:280562253820:ios:eed3a08d4e7e6a6b677c79",
              options.bundleID == Bundle.main.bundleIdentifier else {
            logger.error("Cloud narration configuration identity rejected", category: "cloud_narration")
            return
        }
        if FirebaseApp.app() == nil {
            logger.trace("Firebase attestation provider registration started", category: "cloud_narration", metadata: ["provider": .string("app_attest")])
            AppCheck.setAppCheckProviderFactory(CloudAppCheckProviderFactory())
            FirebaseApp.configure(options: options)
            logger.debug("Firebase application configured", category: "cloud_narration")
        } else {
            logger.trace("Firebase application reused", category: "cloud_narration")
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
            Task { @MainActor [weak self] in
                self?.logger.trace("Firebase authentication state received", category: "cloud_narration", metadata: ["signed_in": .bool(uid != nil)])
                self?.changedAccount(to: uid)
            }
        }
        logger.debug("Cloud narration connections prepared", category: "cloud_narration", metadata: ["region": .string("europe-west1"), "authentication_listener": .bool(authListener != nil), "custom_output_bucket": .bool((Bundle.main.object(forInfoDictionaryKey: "CloudNarrationOutputBucket") as? String)?.isEmpty == false)])
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        logger.trace("Apple sign-in preparation started", category: "cloud_narration")
        guard isConfigured, isEnabled else {
            logger.warning("Apple sign-in unavailable", category: "cloud_narration")
            message = CloudNarrationFailure.unavailable.localizedDescription; return
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            logger.error("Apple sign-in nonce generation failed", error: NSError(domain: NSOSStatusErrorDomain, code: Int(status)), category: "cloud_narration")
            message = String(localized: "Sign-in could not start. Try again."); return
        }
        let nonce = bytes.map { String(format: "%02x", $0) }.joined()
        self.nonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        logger.trace("Apple sign-in request prepared", category: "cloud_narration")
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        let pendingNonce = nonce
        nonce = nil
        let operation = CloudNarrationLogOperation(name: "apple_sign_in")
        logger.debug("Apple sign-in result received", category: "cloud_narration", metadata: operation.metadata)
        guard let auth, isEnabled else {
            logger.warning("Apple sign-in unavailable", category: "cloud_narration", metadata: operation.metadata)
            message = CloudNarrationFailure.unavailable.localizedDescription; return
        }
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
            if previousTask != nil { logger.trace("Previous cloud sign-in attempt cancelled", category: "cloud_narration", metadata: operation.metadata) }
            let attempt = UUID()
            signInAttempt = attempt
            acceptsAuthChanges = false
            isWorking = true
            signInTask = Task { [weak self] in
                // Firebase authentication may finish after cancellation. Serialize attempts so an old
                // result is signed out before a newer attempt can establish another account.
                await previousTask?.value
                guard let self else { return }
                guard self.signInAttempt == attempt, !Task.isCancelled else {
                    self.logger.trace("Cloud sign-in attempt superseded", category: "cloud_narration", metadata: operation.metadata)
                    return
                }
                self.acceptsAuthChanges = true
                defer { if self.signInAttempt == attempt { self.isWorking = false } }
                do {
                    if let current = auth.currentUser {
                        self.logger.trace("Firebase reauthentication started", category: "cloud_narration", metadata: operation.metadata)
                        _ = try await current.reauthenticate(with: credential)
                    } else {
                        self.logger.trace("Firebase authentication started", category: "cloud_narration", metadata: operation.metadata)
                        _ = try await auth.signIn(with: credential)
                    }
                    if Task.isCancelled || self.signInAttempt != attempt {
                        self.logger.trace("Cloud sign-in completion discarded", category: "cloud_narration", metadata: operation.metadata)
                        self.signOutSupersededAttempt(auth, operation: operation)
                        return
                    }
                    self.appleAuthorizationCode = authorizationCode
                    self.changedAccount(to: auth.currentUser?.uid)
                    self.message = nil
                    self.logger.debug("Cloud sign-in completed", category: "cloud_narration", metadata: operation.metadata)
                } catch {
                    let snapshot = ErrorSnapshot(error)
                    if ErrorSnapshot.isCancellation(error) || Task.isCancelled {
                        self.logger.trace("Cloud sign-in attempt cancelled", category: "cloud_narration", metadata: operation.metadata)
                    } else if self.signInAttempt == attempt {
                        self.logger.log(LogEntry("Cloud sign-in failed", level: .error, category: "cloud_narration", metadata: operation.metadata, error: snapshot, source: snapshot.source))
                        self.message = String(localized: "Sign-in could not finish. Try again.")
                    } else {
                        self.logger.trace("Cloud sign-in attempt cancelled", category: "cloud_narration", metadata: operation.metadata)
                    }
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain != ASAuthorizationError.errorDomain || nsError.code != ASAuthorizationError.canceled.rawValue {
                logger.error("Apple sign-in failed", error: error, category: "cloud_narration", metadata: operation.metadata)
                message = String(localized: "Sign-in could not finish. Try again.")
            } else {
                logger.trace("Apple sign-in cancelled", category: "cloud_narration", metadata: operation.metadata)
            }
        }
    }

    func signOut() {
        let operation = CloudNarrationLogOperation(name: "sign_out")
        logger.debug("Cloud sign-out started", category: "cloud_narration", metadata: operation.metadata)
        signInAttempt = UUID()
        acceptsAuthChanges = false
        signInTask?.cancel()
        isWorking = false
        do {
            try auth?.signOut(); changedAccount(to: nil)
            logger.debug("Cloud sign-out completed", category: "cloud_narration", metadata: operation.metadata)
        }
        catch {
            logger.error("Cloud sign-out failed", error: error, category: "cloud_narration", metadata: operation.metadata)
            message = String(localized: "Sign-out could not finish. Try again.")
        }
    }

    func beginEnrollment(name: String, language: String, retentionAccepted: Bool) async throws -> VoiceEnrollment {
        try await withOperation("begin_voice_enrollment") { operation in
            guard retentionAccepted else { throw CloudNarrationFailure.invalidRecording }
            let data = try await call("beginVoiceEnrollment", payload: ["displayName": name, "language": language,
                        "consentVersion": "2026-10-01", "retentionAccepted": retentionAccepted], parent: operation)
            return try decode(VoiceEnrollment.self, data: data, operation: operation)
        }
    }

    func uploadEnrollment(enrollment: VoiceEnrollment, referenceURL: URL, consentURL: URL) async throws -> String {
        try await withOperation("upload_voice_enrollment") { operation in
            let session = try currentSession()
            guard enrollment.expiresAt > Date().timeIntervalSince1970 else { throw CloudNarrationFailure.expired }
            for (kind, url) in [("reference", referenceURL), ("consent", consentURL)] {
                let data: Data
                do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
                catch {
                    throw failure(error, presenting: .invalidRecording)
                }
                guard data.count <= 1_500_000 else { throw CloudNarrationFailure.invalidAudio }
                logger.trace("Enrollment recording read", category: "cloud_narration", metadata: operation.metadata.merging(["recording_kind": .string(kind), "bytes": .integer(data.count)]) { _, new in new })
                try validate(session)
                _ = try await call("uploadEnrollmentRecording", payload: ["enrollmentId": enrollment.enrollmentId,
                                  "kind": kind, "audioBase64": data.base64EncodedString()], parent: operation)
                try validate(session)
            }
            let response = try await call("completeVoiceEnrollment", payload: ["enrollmentId": enrollment.enrollmentId], parent: operation)
            try validate(session)
            guard let id = response["profileId"] as? String else { throw CloudNarrationFailure.invalidResponse }
            logger.debug("Cloud voice worker task accepted", category: "cloud_narration", metadata: operation.metadata.merging(["task_key": .string(CloudNarrationDiagnostics.taskKey(kind: "enroll", uid: session.uid, id: id))]) { _, new in new })
            return id
        }
    }

    func approveVoice(profileID: String) async throws {
        try await withOperation("approve_voice") { operation in _ = try await call("approveVoice", payload: ["profileId": profileID], parent: operation) }
    }

    func startVoicePreview(profileID: String) async throws -> String {
        try await withOperation("start_voice_preview") { _ in
            guard let voice = voices.first(where: { $0.id == profileID }) else { throw CloudNarrationFailure.staleVoice }
            let text = voice.language == "pl-PL"
                ? "Mały lis otulił się ciepłym kocem. Za oknem gwiazdy migotały na niebie. Jesteś bezpieczny, szepnęła mama. Jutro czeka nas nowa przygoda."
                : "The little fox curled up beneath a warm blanket. Outside, the stars sparkled in the sky. You are safe, whispered Mum. Tomorrow brings a new adventure."
            var draft = BookDraft()
            draft.title = String(localized: "Voice Preview")
            draft.chapters = [DraftChapter(title: "", text: text)]
            return try await startNarration(draft: draft, voiceID: profileID, styles: [:], defaultStyle: .gentle, preview: true)
        }
    }

    func startNarration(draft: BookDraft, voiceID: String, styles: [UUID: [NarrationStyle]],
                        defaultStyle: NarrationStyle, preview: Bool) async throws -> String {
        try await withOperation("start_narration", metadata: ["preview": .bool(preview), "chapter_count": .integer(draft.chapters.count)]) { operation in
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
            logger.trace("Narration request prepared", category: "cloud_narration", metadata: operation.metadata.merging(["chapter_count": .integer(chapters.count), "paragraph_count": .integer(chapters.reduce(0) { $0 + $1.paragraphs.count })]) { _, new in new })
            let requestID: String
            do {
                requestID = try NarrationRequestReceipt.requestID(uid: session.uid, draftID: draft.id,
                                                                snapshotHash: hash, voiceID: voiceID, preview: preview)
            } catch {
                throw failure(error, presenting: .retryLater)
            }
            let response = try await call("startNarration", payload: ["requestId": requestID,
                       "voiceProfileId": voiceID, "draftId": draft.id.uuidString, "snapshotHash": hash,
                       "language": voice.language, "preview": preview, "chapters": wireChapters], parent: operation)
            try validate(session)
            guard let id = response["jobId"] as? String else { throw CloudNarrationFailure.invalidResponse }
            logger.debug("Cloud narration worker task accepted", category: "cloud_narration", metadata: operation.metadata.merging(["task_key": .string(CloudNarrationDiagnostics.taskKey(kind: "narrate", uid: session.uid, id: id))]) { _, new in new })
            NarrationRequestReceipt.confirm(uid: session.uid, requestID: requestID)
            return id
        }
    }

    func snapshotHash(draft: BookDraft, styles: [UUID: [NarrationStyle]], defaultStyle: NarrationStyle) -> String {
        do { return try NarrationSnapshot(draft: draft, styles: styles, defaultStyle: defaultStyle).hash }
        catch {
            logger.error("Narration snapshot hashing failed", error: error, category: "cloud_narration")
            return ""
        }
    }

    func cancel(jobID: String) async throws {
        try await withOperation("cancel_narration") { operation in _ = try await call("cancelNarration", payload: ["jobId": jobID], parent: operation) }
    }
    func deleteVoice(profileID: String) async throws {
        try await withOperation("delete_voice") { operation in _ = try await call("deleteVoice", payload: ["profileId": profileID], parent: operation) }
    }

    func deleteAccount() async throws {
        try await withOperation("delete_account") { operation in
            guard let auth, let code = appleAuthorizationCode else {
                message = String(localized: "Confirm with Apple before deleting your voice account.")
                throw CloudNarrationFailure.signInRequired
            }
            // Apple's authorization is separate from deleting our private cloud data.
            let session = try currentSession()
            logger.trace("Apple account revocation started", category: "cloud_narration", metadata: operation.metadata)
            do { try await auth.revokeToken(withAuthorizationCode: code) }
            catch {
                throw failure(error, presenting: .confirmWithApple)
            }
            logger.trace("Apple account revocation completed", category: "cloud_narration", metadata: operation.metadata)
            try validate(session)
            appleAuthorizationCode = nil
            _ = try await call("deleteAccount", payload: [:], parent: operation)
            signOut()
        }
    }

    func download(job: NarrationJob) async throws -> [UUID: URL] {
        try await withOperation("download_narration", metadata: ["output_count": .integer(job.outputs.count)]) { operation in
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
                throw failure(error, presenting: .retryLater)
            }
            logger.trace("Narration cache prepared", category: "cloud_narration", metadata: operation.metadata)
            var results: [UUID: URL] = [:]
            do {
                for (index, output) in job.outputs.enumerated() {
                    try validate(session)
                    guard let chapterID = UUID(uuidString: output.chapterId),
                          output.path == "users/\(session.uid)/jobs/\(job.id)/\(output.chapterId).m4a",
                          output.bytes > 0, output.bytes <= 100_000_000, output.duration > 0,
                          results[chapterID] == nil else { throw CloudNarrationFailure.invalidAudio }
                    let url = directory.appendingPathComponent(chapterID.uuidString + ".m4a")
                    try await download(storage.reference(withPath: output.path), to: url, session: session, parent: operation, index: index, expectedBytes: output.bytes)
                    try validate(session)
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count == output.bytes,
                          SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == output.sha256 else {
                        throw CloudNarrationFailure.invalidAudio
                    }
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
                    results[chapterID] = url
                    logger.trace("Narration output verified", category: "cloud_narration", metadata: operation.metadata.merging(["output_index": .integer(index), "bytes": .integer(data.count)]) { _, new in new })
                }
                try validate(session)
                return results
            } catch {
                let evidence = ErrorSnapshot(error)
                removePrivateCache(directory, operation: operation)
                // Keep the recovery for account replacement while retaining the original download evidence.
                do { try validate(session) }
                catch {
                    if error is CancellationError { throw error }
                    throw CloudNarrationFailureContext(presentation: error, underlyingLogError: evidence)
                }
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let failure = error as? CloudNarrationFailure { throw failure }
                if error is CloudNarrationFailureContext { throw error }
                throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.retryLater, underlyingLogError: evidence)
            }
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

    private func call(_ name: String, payload: [String: Any], parent: CloudNarrationLogOperation) async throws -> [String: Any] {
        let operation = CloudNarrationLogOperation(name: name)
        let metadata = operation.metadata.merging(["parent_operation_id": .string(parent.id), "transport": .string("firebase_callable"), "attestation_required": .bool(true), "timeout_seconds": .integer(90)]) { _, new in new }
        logger.trace("Cloud callable preparation started", category: "cloud_narration", metadata: metadata)
        let session = try currentSession()
        guard let functions else { throw CloudNarrationFailure.unavailable }
        let callable = functions.httpsCallable(name, options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true))
        callable.timeoutInterval = 90
        let result: HTTPSCallableResult
        do {
            // Reconstitute a disconnected JSON value before transferring it to the SDK's concurrent API.
            let json = try JSONSerialization.data(withJSONObject: payload)
            logger.trace("Cloud callable dispatch started", category: "cloud_narration", metadata: metadata.merging(["payload_bytes": .integer(json.count)]) { _, new in new })
            result = try await callable.call(JSONSerialization.jsonObject(with: json))
        }
        catch {
            let evidence = ErrorSnapshot(error)
            logger.trace("Cloud callable dispatch failed", category: "cloud_narration", metadata: operation.metadata.merging(["parent_operation_id": .string(parent.id)]) { _, new in new })
            if ErrorSnapshot.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            do { try validate(session) }
            catch {
                if error is CancellationError { throw error }
                throw CloudNarrationFailureContext(presentation: error, underlyingLogError: evidence)
            }
            let code = (error as NSError).code
            switch FunctionsErrorCode(rawValue: code) {
            case .unauthenticated: throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.signInRequired, underlyingLogError: evidence)
            case .permissionDenied: throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.permissionDenied, underlyingLogError: evidence)
            case .resourceExhausted: throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.limitReached, underlyingLogError: evidence)
            case .invalidArgument: throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.invalidRecording, underlyingLogError: evidence)
            case .failedPrecondition:
                if name == "deleteVoice" || name == "deleteAccount" { throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.confirmWithApple, underlyingLogError: evidence) }
                throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.unavailable, underlyingLogError: evidence)
            default: throw CloudNarrationFailureContext(presentation: CloudNarrationFailure.retryLater, underlyingLogError: evidence)
            }
        }
        try validate(session)
        guard let data = result.data as? [String: Any] else { throw CloudNarrationFailure.invalidResponse }
        logger.debug("Cloud callable completed", category: "cloud_narration", metadata: operation.metadata.merging(["parent_operation_id": .string(parent.id), "field_count": .integer(data.count)]) { _, new in new })
        return data
    }

    private func changedAccount(to uid: String?) {
        guard uid == auth?.currentUser?.uid else {
            logger.trace("Stale authentication state discarded", category: "cloud_narration")
            return
        }
        if uid != nil, !acceptsAuthChanges {
            if let auth { signOutSupersededAttempt(auth, operation: CloudNarrationLogOperation(name: "discard_auth_change")) }
            return
        }
        guard userID != uid else {
            logger.trace("Unchanged authentication state received", category: "cloud_narration")
            return
        }
        let operation = CloudNarrationLogOperation(name: "account_change")
        logger.debug("Cloud narration account state changed", category: "cloud_narration", metadata: operation.metadata.merging(["signed_in": .bool(uid != nil), "active_download_count": .integer(downloads.count)]) { _, new in new })
        accountGeneration = UUID()
        logger.trace("Cloud narration listeners detached", category: "cloud_narration", metadata: operation.metadata.merging(["voice_listener": .bool(voiceListener != nil), "job_listener": .bool(jobListener != nil)]) { _, new in new })
        voiceListener?.remove(); jobListener?.remove()
        voiceListener = nil; jobListener = nil
        for task in downloads.values { task.cancel() }
        downloads.removeAll()
        observedVoiceStates.removeAll(); observedJobStates.removeAll()
        observedVoiceFailureCodes.removeAll(); observedJobFailureCodes.removeAll()
        voices = []; jobs = []; message = nil
        let oldUID = userID
        userID = uid
        if let oldUID {
            appleAuthorizationCode = nil
            NarrationDraftPreferences.removePrivateData(userID: oldUID)
            NarrationRequestReceipt.removePrivateData(uid: oldUID)
            do { removePrivateCache(try privateCache(for: oldUID), operation: operation) }
            catch { logger.warning("Private narration cache cleanup failed", error: error, category: "cloud_narration", metadata: operation.metadata) }
        }
        guard let uid, let database, isEnabled else { return }
        let generation = accountGeneration
        let voiceOperation = CloudNarrationLogOperation(name: "voice_listener")
        logger.trace("Voice profiles listener attaching", category: "cloud_narration", metadata: voiceOperation.metadata)
        voiceListener = database.collection("users/\(uid)/voices").addSnapshotListener { [weak self] snapshot, error in
            let decoded = Self.decodeSnapshot(VoiceProfile.self, snapshot: snapshot)
            let failure = error.map { ErrorSnapshot($0) }
            let cancelled = error.map { ErrorSnapshot.isCancellation($0) } ?? false
            let fromCache = snapshot?.metadata.isFromCache ?? false
            let pendingWrites = snapshot?.metadata.hasPendingWrites ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.userID == uid, self.accountGeneration == generation else {
                    self.logger.trace("Stale voice profiles snapshot discarded", category: "cloud_narration", metadata: voiceOperation.metadata)
                    return
                }
                self.logSnapshotDecodingFailures(decoded.failures, operation: voiceOperation)
                if cancelled {
                    self.logger.trace("Voice profiles listener cancelled", category: "cloud_narration", metadata: voiceOperation.metadata)
                } else if let failure {
                    self.logger.log(LogEntry("Voice profiles load failed", level: .error, category: "cloud_narration", metadata: voiceOperation.metadata, error: failure, source: failure.source))
                    self.voices = []; self.message = String(localized: "Your voices could not be loaded. Try again.")
                }
                else {
                    self.logVoiceStateChanges(decoded.values, uid: uid, operation: voiceOperation)
                    self.voices = decoded.values.sorted { $0.createdAt > $1.createdAt }
                    self.logger.debug("Voice profiles snapshot received", category: "cloud_narration", metadata: voiceOperation.metadata.merging(["document_count": .integer(decoded.values.count + decoded.failures.count), "decoded_count": .integer(decoded.values.count), "from_cache": .bool(fromCache), "pending_writes": .bool(pendingWrites)]) { _, new in new })
                }
            }
        }
        let jobOperation = CloudNarrationLogOperation(name: "job_listener")
        logger.trace("Narration jobs listener attaching", category: "cloud_narration", metadata: jobOperation.metadata)
        jobListener = database.collection("users/\(uid)/jobs").addSnapshotListener { [weak self] snapshot, error in
            let decoded = Self.decodeSnapshot(NarrationJob.self, snapshot: snapshot)
            let failure = error.map { ErrorSnapshot($0) }
            let cancelled = error.map { ErrorSnapshot.isCancellation($0) } ?? false
            let fromCache = snapshot?.metadata.isFromCache ?? false
            let pendingWrites = snapshot?.metadata.hasPendingWrites ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.userID == uid, self.accountGeneration == generation else {
                    self.logger.trace("Stale narration jobs snapshot discarded", category: "cloud_narration", metadata: jobOperation.metadata)
                    return
                }
                self.logSnapshotDecodingFailures(decoded.failures, operation: jobOperation)
                if cancelled {
                    self.logger.trace("Narration jobs listener cancelled", category: "cloud_narration", metadata: jobOperation.metadata)
                } else if let failure {
                    self.logger.log(LogEntry("Narration jobs load failed", level: .error, category: "cloud_narration", metadata: jobOperation.metadata, error: failure, source: failure.source))
                    self.jobs = []; self.message = String(localized: "Your narrations could not be loaded. Try again.")
                }
                else {
                    self.logJobStateChanges(decoded.values, uid: uid, operation: jobOperation)
                    self.jobs = decoded.values.sorted { $0.createdAt > $1.createdAt }
                    NarrationRequestReceipt.confirm(uid: uid, requestIDs: Set(decoded.values.map(\.id)))
                    self.logger.debug("Narration jobs snapshot received", category: "cloud_narration", metadata: jobOperation.metadata.merging(["document_count": .integer(decoded.values.count + decoded.failures.count), "decoded_count": .integer(decoded.values.count), "from_cache": .bool(fromCache), "pending_writes": .bool(pendingWrites)]) { _, new in new })
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
    nonisolated private static func decodeSnapshot<T: Decodable & Sendable>(_ type: T.Type, snapshot: QuerySnapshot?) -> (values: [T], failures: [(index: Int, error: ErrorSnapshot)]) {
        var values: [T] = []
        var failures: [(index: Int, error: ErrorSnapshot)] = []
        for (index, document) in (snapshot?.documents ?? []).enumerated() {
            var data = document.data(); data["id"] = document.documentID
            do { values.append(try decodeDocument(type, data: data)) }
            catch { failures.append((index, ErrorSnapshot(error))) }
        }
        return (values, failures)
    }

    private func logSnapshotDecodingFailures(_ failures: [(index: Int, error: ErrorSnapshot)], operation: CloudNarrationLogOperation) {
        for failure in failures {
            logger.log(LogEntry("Cloud narration document decoding failed", level: .error, category: "cloud_narration",
                                metadata: operation.metadata.merging(["document_index": .integer(failure.index)]) { _, new in new },
                                error: failure.error, source: failure.error.source))
        }
    }

    private func logVoiceStateChanges(_ profiles: [VoiceProfile], uid: String, operation: CloudNarrationLogOperation) {
        for voice in profiles {
            let previous = observedVoiceStates[voice.id]
            let safeFailureCode = CloudNarrationBackendFailure.safeCode(voice.errorCode)
            guard previous != voice.status || (voice.status == "failed" && observedVoiceFailureCodes[voice.id] != safeFailureCode) else { continue }
            observedVoiceStates[voice.id] = voice.status
            observedVoiceFailureCodes[voice.id] = voice.status == "failed" ? safeFailureCode : nil
            let safeStates = ["processing", "awaitingApproval", "ready", "failed", "deleting", "deleted"]
            let metadata = operation.metadata.merging([
                "task_key": .string(CloudNarrationDiagnostics.taskKey(kind: "enroll", uid: uid, id: voice.id)),
                "state": .string(safeStates.contains(voice.status) ? voice.status : "unknown"),
                "previous_state": .string(previous.flatMap { safeStates.contains($0) ? $0 : nil } ?? "unobserved")
            ]) { _, new in new }
            if voice.status == "failed" {
                logger.error("Cloud voice worker reported failure", error: CloudNarrationBackendFailure(), category: "cloud_narration", metadata: metadata.merging(["backend_error_code": .string(safeFailureCode), "failure_evidence": .string("server_state")]) { _, new in new })
            } else {
                logger.debug("Cloud voice state changed", category: "cloud_narration", metadata: metadata)
            }
        }
    }

    private func logJobStateChanges(_ jobs: [NarrationJob], uid: String, operation: CloudNarrationLogOperation) {
        for job in jobs {
            let previous = observedJobStates[job.id]
            let safeFailureCode = CloudNarrationBackendFailure.safeCode(job.errorCode)
            guard previous != job.state || (job.state == "failed" && observedJobFailureCodes[job.id] != safeFailureCode) else { continue }
            observedJobStates[job.id] = job.state
            observedJobFailureCodes[job.id] = job.state == "failed" ? safeFailureCode : nil
            let safeStates = ["queued", "processing", "ready", "failed", "cancelled", "expired"]
            let metadata = operation.metadata.merging([
                "task_key": .string(CloudNarrationDiagnostics.taskKey(kind: "narrate", uid: uid, id: job.id)),
                "state": .string(safeStates.contains(job.state) ? job.state : "unknown"),
                "previous_state": .string(previous.flatMap { safeStates.contains($0) ? $0 : nil } ?? "unobserved")
            ]) { _, new in new }
            if job.state == "failed" {
                logger.error("Cloud narration worker reported failure", error: CloudNarrationBackendFailure(), category: "cloud_narration", metadata: metadata.merging(["backend_error_code": .string(safeFailureCode), "failure_evidence": .string("server_state")]) { _, new in new })
            } else if job.state == "cancelled" {
                logger.trace("Cloud narration worker cancellation received", category: "cloud_narration", metadata: metadata)
            } else {
                logger.debug("Cloud narration job state changed", category: "cloud_narration", metadata: metadata)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, data: [String: Any], operation: CloudNarrationLogOperation) throws -> T {
        logger.trace("Cloud narration response decoding started", category: "cloud_narration", metadata: operation.metadata)
        do {
            let decoded = try Self.decodeDocument(type, data: data)
            logger.trace("Cloud narration response decoding completed", category: "cloud_narration", metadata: operation.metadata)
            return decoded
        }
        catch {
            throw failure(error, presenting: .invalidResponse)
        }
    }

    private func withOperation<T>(_ name: String, metadata: [String: TelemetryValue] = [:],
                                  file: String = #fileID, function: String = #function, line: UInt = #line,
                                  body: (CloudNarrationLogOperation) async throws -> T) async throws -> T {
        let operation = CloudNarrationLogOperation(name: name)
        logger.debug("Cloud narration operation started", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new }, file: file, function: function, line: line)
        do {
            let result = try await body(operation)
            logger.debug("Cloud narration operation completed", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new }, file: file, function: function, line: line)
            return result
        } catch {
            if ErrorSnapshot.isCancellation(error) || Task.isCancelled {
                logger.trace("Cloud narration operation cancelled", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new }, file: file, function: function, line: line)
                throw CancellationError()
            }
            if error is CloudNarrationReportedFailure {
                logger.trace("Cloud narration operation stopped after reported failure", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new }, file: file, function: function, line: line)
                throw error
            }
            let snapshot = ErrorSnapshot(error, file: file, function: function, line: line)
            logger.log(LogEntry("Cloud narration operation failed", level: .error, category: "cloud_narration",
                                metadata: operation.metadata.merging(metadata) { _, new in new },
                                error: snapshot, source: snapshot.source))
            throw CloudNarrationReportedFailure(presentation: error, underlyingLogError: snapshot)
        }
    }

    private func failure(_ error: any Error, presenting presentation: CloudNarrationFailure,
                         file: String = #fileID, function: String = #function, line: UInt = #line) -> CloudNarrationFailureContext {
        CloudNarrationFailureContext(presentation: presentation, underlyingLogError: ErrorSnapshot(error, file: file, function: function, line: line))
    }

    private func signOutSupersededAttempt(_ auth: Auth, operation: CloudNarrationLogOperation) {
        do {
            try auth.signOut()
            logger.trace("Superseded authentication session signed out", category: "cloud_narration", metadata: operation.metadata)
        } catch {
            logger.error("Superseded authentication sign-out failed", error: error, category: "cloud_narration", metadata: operation.metadata)
        }
    }

    private func removePrivateCache(_ directory: URL, operation: CloudNarrationLogOperation) {
        do {
            try FileManager.default.removeItem(at: directory)
            logger.trace("Private narration cache removed", category: "cloud_narration", metadata: operation.metadata)
        } catch {
            let nsError = error as NSError
            guard nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileNoSuchFileError else { return }
            logger.warning("Private narration cache removal failed", error: error, category: "cloud_narration", metadata: operation.metadata)
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

    private func download(_ reference: StorageReference, to url: URL, session: Session,
                          parent: CloudNarrationLogOperation, index: Int, expectedBytes: Int) async throws {
        let id = UUID()
        let operation = CloudNarrationLogOperation(name: "storage_download")
        let metadata: [String: TelemetryValue] = ["parent_operation_id": .string(parent.id), "output_index": .integer(index), "expected_bytes": .integer(expectedBytes)]
        logger.trace("Narration storage download started", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new })
        defer { downloads[id] = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = reference.write(toFile: url) { _, error in
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == StorageErrorDomain && nsError.code == StorageErrorCode.cancelled.rawValue {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            // Capture on the SDK callback stack before crossing the continuation.
                            continuation.resume(throwing: CloudNarrationFailureContext(presentation: CloudNarrationFailure.retryLater, underlyingLogError: ErrorSnapshot(error)))
                        }
                    }
                    else { continuation.resume() }
                }
                downloads[id] = task
                if Task.isCancelled { task.cancel() }
            }
            try validate(session)
            logger.trace("Narration storage download completed", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new })
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.logger.trace("Narration storage download cancellation requested", category: "cloud_narration", metadata: operation.metadata.merging(metadata) { _, new in new })
                self?.downloads[id]?.cancel()
            }
        }
    }
}
