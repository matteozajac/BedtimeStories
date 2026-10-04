import Foundation
import Observation
import UIKit
import UserNotifications

@Observable @MainActor
final class OperationCenter {
    static let shared = OperationCenter()
    private(set) var operations: [AppOperation] = []
    var banner: AppOperation?
    var showingOperations = false
    var requestedDestination: OperationDestination?
    var message: String?
    var completionAlertsEnabled: Bool {
        didSet { defaults.set(completionAlertsEnabled, forKey: "operationCompletionAlerts")
            Task { await OperationNotifications.current?.registerDevice() } }
    }
    private(set) var notificationsEnabled = false
    private(set) var ownerGeneration = UUID()
    private(set) var currentOwnerID: String?
    @ObservationIgnored private var deferredRemoteRoute: (id: String, owner: String)?
    @ObservationIgnored private var cancellingRemote: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var remoteCancellation: (@MainActor (AppOperation) async throws -> Void)?
    @ObservationIgnored private var navigationPreparation: (id: UUID, action: @MainActor () async throws -> Void)?
    @ObservationIgnored private var discardedDraftDestinations: [String: OperationDestination] = [:]
    @ObservationIgnored private let runtime = ContinuedOperationRuntime()
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let systemEnabled: Bool
    @ObservationIgnored private var active = true
    @ObservationIgnored private var activityDriver: OperationLiveActivities?

    init(directory: URL? = nil, defaults: UserDefaults = .standard, systemEnabled: Bool = true) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Operations", isDirectory: true)
        self.defaults = defaults
        self.systemEnabled = systemEnabled
        completionAlertsEnabled = defaults.object(forKey: "operationCompletionAlerts") as? Bool ?? true
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("discarded-drafts.json")),
           let destinations = try? JSONDecoder().decode([String: OperationDestination].self, from: data) {
            discardedDraftDestinations = destinations
        }
        do {
            let data = try Data(contentsOf: self.directory.appendingPathComponent("operations.json"))
            operations = try JSONDecoder().decode([AppOperation].self, from: data)
            for index in operations.indices where operations[index].isActive && operations[index].remoteID == nil {
                operations[index].state = .interrupted
                operations[index].message = String(localized: "This operation was interrupted. Your saved work is safe; open it to try again.")
            }
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError { AppLog.warning("Operation history could not be loaded", error: error, category: "operations") }
        }
    }
    var visibleOperations: [AppOperation] { operations.filter { $0.hiddenFromHistory != true && ($0.ownerID == nil || $0.ownerID == currentOwnerID) }.sorted { $0.createdAt > $1.createdAt } }
    var activeOperations: [AppOperation] { visibleOperations.filter(\.isActive) }
    var completedOperations: [AppOperation] { visibleOperations.filter(\.isTerminal) }

    func configure(cloud: CloudNarrationModel) {
        remoteCancellation = { operation in
            guard let id = operation.remoteID else { return }
            switch operation.kind {
            case .storyGeneration: try await cloud.cancelStory(jobID: id)
            case .narration, .voicePreview: try await cloud.cancel(jobID: id)
            case .voiceEnrollment: try await cloud.deleteVoice(profileID: id)
            default: throw CloudNarrationFailure.retryLater
            }
        }
        if systemEnabled { activityDriver = OperationLiveActivities(cloud: cloud) }
    }
    func changedOwner(_ owner: String?) {
        guard currentOwnerID != owner else { return }
        let previous = currentOwnerID
        ownerGeneration = UUID()
        currentOwnerID = owner
        if let route = deferredRemoteRoute, let owner, route.owner != owner { deferredRemoteRoute = nil }
        for operation in operations where operation.ownerID == previous && previous != nil {
            tasks[operation.id]?.cancel()
            runtime.end(id: operation.id, success: false)
            activityDriver?.end(operation)
        }
        banner = nil; requestedDestination = nil
        fulfillRemoteRoute()
    }
    func sceneChanged(active: Bool) {
        self.active = active
        if active {
            Task { await refreshNotificationAuthorization(); await OperationNotifications.current?.registerDevice() }
            expireRemoteOperations()
            activityDriver?.restore(activeOperations)
        }
    }

    @discardableResult
    func begin(kind: AppOperation.Kind, title: String, subtitle: String, destination: OperationDestination,
               ownerID: String? = nil, id: String = UUID().uuidString, progress: Double? = nil) -> String {
        guard !operations.contains(where: { $0.id == id }) else { return id }
        var operation = AppOperation(id: id, kind: kind, title: title, subtitle: subtitle, progress: progress,
                                     destination: destination, ownerID: ownerID)
        if let replacement = discardedDestination(destination, ownerID: ownerID) {
            operation.state = .cancelled; operation.hiddenFromHistory = true; operation.destination = replacement
        }
        operations.append(operation)
        persist()
        return id
    }
    @discardableResult
    func start(kind: AppOperation.Kind, title: String, subtitle: String, destination: OperationDestination,
               ownerID: String? = nil, id: String = UUID().uuidString,
               work: @escaping @MainActor (String) async throws -> Void) -> String {
        guard !operations.contains(where: { $0.id == id }) else { return id }
        let id = begin(kind: kind, title: title, subtitle: subtitle, destination: destination, ownerID: ownerID, id: id)
        run(id: id, work: work)
        return id
    }
    func beginExternal(_ id: String) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        // Atomic publication is owned by the editor, not a cancellable center task.
        operations[index].cancellationDisabled = true
        persist()
        guard systemEnabled else { return }
        let operation = operations[index]
        runtime.begin(id: id, title: operation.title, subtitle: operation.subtitle) { [weak self] in
            // Ending the system grant does not imply the atomic save stopped.
            self?.runtime.end(id: id, success: false)
        }
    }
    func endExternal(_ id: String, success: Bool) { runtime.end(id: id, success: success) }
    func run(id: String, work: @escaping @MainActor (String) async throws -> Void) {
        guard tasks[id] == nil, let operation = operations.first(where: { $0.id == id }),
              !(operation.state == .cancelled && operation.hiddenFromHistory == true) else { return }
        update(id, state: .running)
        if systemEnabled { runtime.begin(id: id, title: operation.title, subtitle: operation.subtitle) { [weak self] in self?.interrupt(id) } }
        let generation = ownerGeneration
        tasks[id] = Task {
            do {
                try await work(id)
                try Task.checkCancellation()
                if operations.first(where: { $0.id == id })?.remoteID == nil { update(id, state: .ready, progress: 1) }
            } catch {
                if error is CancellationError || Task.isCancelled {
                    let current = operations.first { $0.id == id }
                    if current?.state != .interrupted && !(generation != ownerGeneration && current?.remoteID != nil) { update(id, state: .cancelled) }
                } else {
                    AppLog.error("Background operation failed", error: error, category: "operations", metadata: ["operation_kind": .string(operation.kind.rawValue)])
                    update(id, state: .failed, message: error.localizedDescription)
                }
            }
            runtime.end(id: id, success: operations.first(where: { $0.id == id }).map { $0.state == .ready || ($0.remoteID != nil && $0.isActive) } ?? false)
            tasks[id] = nil
        }
    }
    func trackRemoteSubmission(_ id: String, remoteID: String) {
        let remoteID = UUID(uuidString: remoteID)?.uuidString.lowercased() ?? remoteID
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].remoteID = remoteID
        operations[index].remoteExpiresAt = operations[index].remoteExpiresAt ?? Date().addingTimeInterval(24 * 60 * 60)
        persist()
    }
    func refreshLiveActivityRegistrations() { activityDriver?.refreshRegistrations(activeOperations) }
    func attachRemote(_ id: String, remoteID: String) {
        let remoteID = UUID(uuidString: remoteID)?.uuidString.lowercased() ?? remoteID
        guard let original = operations.first(where: { $0.id == id }) else { return }
        let peers = operations.filter { $0.id != id && $0.remoteID == remoteID && $0.ownerID == original.ownerID &&
            ($0.kind == original.kind || (original.kind == .voicePreview && $0.kind == .narration)) }
        if !(original.state == .cancelled && original.hiddenFromHistory == true) {
            if let peer = peers.max(by: { $0.updatedAt < $1.updatedAt }),
               let index = operations.firstIndex(where: { $0.id == id }) {
                operations[index].state = peer.state
                operations[index].progress = peer.progress
                operations[index].remoteExpiresAt = peer.remoteExpiresAt
                operations[index].completionPresentedAt = peer.completionPresentedAt
                operations[index].message = peer.message
            } else if let index = operations.firstIndex(where: { $0.id == id }) { operations[index].state = .queued }
        }
        let peerIDs = Set(peers.map(\.id))
        operations.removeAll { peerIDs.contains($0.id) }
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].remoteID = remoteID
        operations[index].remoteExpiresAt = operations[index].remoteExpiresAt ?? Date().addingTimeInterval(24 * 60 * 60)
        if original.state == .cancelled { operations[index].state = .cancelled }
        operations[index].updatedAt = Date()
        if let banner, peerIDs.contains(banner.id) {
            self.banner = operations[index].hiddenFromHistory == true ? nil : operations[index]
        }
        persist()
        fulfillRemoteRoute()
        let operation = operations[index]
        runtime.end(id: id, success: operation.state != .cancelled)
        if operation.state == .cancelled {
            activityDriver?.end(operation)
            retryRemoteCancellation(operation)
        } else if systemEnabled { activityDriver?.start(operation) }
    }
    func setRemoteExpiry(_ id: String, timestamp: Double) {
        guard timestamp > 0, let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].remoteExpiresAt = Date(timeIntervalSince1970: timestamp)
        persist()
    }
    func expireRemoteOperations() {
        for operation in operations where operation.ownerID == currentOwnerID && operation.isActive && operation.remoteExpiresAt.map({ $0 <= Date() }) == true {
            update(operation.id, state: .failed, message: String(localized: "This operation expired before its result could be saved. Open it to try again."))
        }
    }
    func update(_ id: String, state: AppOperation.State? = nil, progress: Double? = nil,
                subtitle: String? = nil, message: String? = nil, destination: OperationDestination? = nil, title: String? = nil) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        // Discard receipts are terminal even if an owned task or server reply arrives late.
        guard !(operations[index].state == .cancelled && operations[index].hiddenFromHistory == true) else { return }
        let previous = operations[index].state
        if let state { operations[index].state = state }
        if let progress { operations[index].progress = min(1, max(0, progress)) }
        if let subtitle { operations[index].subtitle = subtitle }
        if let message { operations[index].message = message }
        else if let state, state == .queued || state == .running || state == .ready { operations[index].message = nil }
        if let destination { operations[index].destination = destination }
        if let title { operations[index].title = title }
        operations[index].updatedAt = Date()
        let operation = operations[index]
        persist()
        fulfillRemoteRoute()
        runtime.update(id: id, progress: operation.progress, title: operation.title, subtitle: operation.subtitle)
        if systemEnabled { activityDriver?.update(operation) }
        if previous != operation.state && (previous == .running || previous == .queued) && (operation.state == .ready || operation.state == .failed) {
            if operation.ownerID == nil || operation.ownerID == currentOwnerID {
                if active, operation.completionPresentedAt == nil { banner = operation; markCompletionPresented(operation.id) }
                else if operation.remoteID == nil { notify(operation) }
            }
        }
    }
    func setReadingPace(_ id: String, value: Int) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].readingWordsPerMinute = value; persist()
    }
    func cancel(id: String) {
        guard let operation = visibleOperations.first(where: { $0.id == id }), operation.canCancel else { return }
        tasks[id]?.cancel()
        update(id, state: .cancelled)
        if operation.remoteID != nil { retryRemoteCancellation(operation) }
    }
    /// A cancellation receipt must survive a callable response or snapshot arriving late.
    func shouldReconcileRemote(_ operationID: String, state: String) -> Bool {
        guard let operation = operations.first(where: { $0.id == operationID }) else { return true }
        guard operation.state == .cancelled else { return true }
        if state == "queued" || state == "processing" { retryRemoteCancellation(operation) }
        return false
    }
    private func retryRemoteCancellation(_ operation: AppOperation) {
        guard operation.ownerID == currentOwnerID, cancellingRemote.insert(operation.id).inserted else { return }
        let generation = ownerGeneration
        Task {
            defer { cancellingRemote.remove(operation.id) }
            do {
                guard let remoteCancellation else { throw CloudNarrationFailure.unavailable }
                try await remoteCancellation(operation)
            } catch {
                guard generation == ownerGeneration else { return }
                AppLog.warning("Remote cancellation is awaiting reconciliation", error: error, category: "operations")
            }
        }
    }

    func cancelPendingVoiceUploads(ownerID: String) {
        for operation in operations where operation.ownerID == ownerID && operation.kind == .voiceEnrollment {
            tasks[operation.id]?.cancel()
            if operation.isActive || operation.state == .interrupted { update(operation.id, state: .cancelled) }
            runtime.end(id: operation.id, success: false)
        }
    }
    private func interrupt(_ id: String) {
        tasks[id]?.cancel()
        update(id, state: .interrupted, message: String(localized: "iOS paused this operation. Your saved work is safe; open it to try again."))
        runtime.end(id: id, success: false)
    }
    func routeNotification(operationID: String, ownerID: String?) {
        if let ownerID {
            guard currentOwnerID == nil || ownerID == currentOwnerID else { return }
            deferredRemoteRoute = (operationID, ownerID)
            fulfillRemoteRoute()
        } else { openOperation(id: operationID) }
    }
    private func fulfillRemoteRoute() {
        guard let route = deferredRemoteRoute, route.owner == currentOwnerID,
              let operation = operations.first(where: { ($0.ownerID == nil || $0.ownerID == currentOwnerID) && ($0.id == route.id || $0.remoteID == route.id) }),
              operation.kind != .storyGeneration || operation.isTerminal else { return }
        deferredRemoteRoute = nil; openOperation(id: route.id)
    }
    func dismissBanner() { banner = nil }
    func clearHistory() {
        for index in operations.indices where operations[index].isTerminal && operations[index].remoteID != nil && (operations[index].ownerID == nil || operations[index].ownerID == currentOwnerID) {
            // Keep a receipt for cloud replay without retaining a visible history row.
            operations[index].hiddenFromHistory = true
        }
        operations.removeAll { $0.isTerminal && $0.remoteID == nil && $0.hiddenFromHistory != true && ($0.ownerID == nil || $0.ownerID == currentOwnerID) }
        persist()
    }
    /// An explicit discard retires receipts before removing their draft. Server replay
    /// and notification taps retain a safe destination after the editing copy is gone.
    func retireDraftOperations(_ draftID: UUID, sourceBookID: UUID? = nil, draftDeleted: Bool = true) {
        let replacement: OperationDestination = sourceBookID.map(OperationDestination.book) ?? (draftDeleted ? .operations : .draft(draftID))
        if draftDeleted {
            discardedDraftDestinations[discardedDraftKey(draftID, ownerID: currentOwnerID)] = replacement
            discardedDraftDestinations[discardedDraftKey(draftID, ownerID: nil)] = replacement
        }
        let retiring = operations.filter {
            ($0.ownerID == nil || $0.ownerID == currentOwnerID) &&
            ($0.destination == .draft(draftID) || $0.destination == .narration(draftID))
        }
        let ids = Set(retiring.map(\.id))
        for operation in retiring {
            tasks[operation.id]?.cancel()
            guard let index = operations.firstIndex(where: { $0.id == operation.id }) else { continue }
            operations[index].state = .cancelled
            operations[index].hiddenFromHistory = true
            operations[index].completionPresentedAt = Date()
            operations[index].destination = replacement
            operations[index].message = nil
            operations[index].updatedAt = Date()
            runtime.end(id: operation.id, success: false)
            activityDriver?.end(operation)
            if operation.isActive && operation.remoteID != nil { retryRemoteCancellation(operations[index]) }
        }
        if let banner, ids.contains(banner.id) { self.banner = nil }
        if requestedDestination == .draft(draftID) || requestedDestination == .narration(draftID) { requestedDestination = replacement }
        persist()
        if systemEnabled {
            let notificationIDs = ids.map { "operation-" + $0 }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notificationIDs)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIDs)
        }
    }
    private func discardedDraftKey(_ draftID: UUID, ownerID: String?) -> String {
        (ownerID ?? "") + ":" + draftID.uuidString
    }
    func clearDraftDiscardMarker(_ draftID: UUID, ownerID: String?) {
        discardedDraftDestinations[discardedDraftKey(draftID, ownerID: ownerID)] = nil
        discardedDraftDestinations[discardedDraftKey(draftID, ownerID: nil)] = nil
        persist()
    }
    private func discardedDestination(_ destination: OperationDestination, ownerID: String?) -> OperationDestination? {
        switch destination {
        case .draft(let id), .narration(let id): discardedDraftDestinations[discardedDraftKey(id, ownerID: ownerID)]
        default: nil
        }
    }
    func markDraftPublished(_ draftID: UUID, bookID: UUID) {
        for index in operations.indices {
            if operations[index].destination == .draft(draftID) || operations[index].destination == .narration(draftID) {
                operations[index].destination = .book(bookID)
            }
        }
        persist()
    }
    func consumeDestination() { requestedDestination = nil }
    func setNavigationPreparation(id: UUID, action: @escaping @MainActor () async throws -> Void) { navigationPreparation = (id, action) }
    func clearNavigationPreparation(id: UUID) { if navigationPreparation?.id == id { navigationPreparation = nil } }
    func openOperation(id: String) {
        let generation = ownerGeneration
        Task {
            do {
                try await navigationPreparation?.action()
                guard generation == ownerGeneration else { return }
                let destination = operations.first(where: { ($0.ownerID == nil || $0.ownerID == currentOwnerID) && ($0.id == id || $0.remoteID == id) })?.destination ?? .operations
                let operation = operations.first { $0.id == id || $0.remoteID == id }
                banner = nil; requestedDestination = operation?.kind == .storyGeneration && operation?.isActive == true ? .operations : destination
            }
            catch { guard generation == ownerGeneration else { return }; message = String(localized: "Your current draft could not be saved. Keep the editor open and try again.") }
        }
    }
    func handle(_ url: URL) -> Bool {
        guard let id = AppOperation.operationID(from: url) else { return false }
        openOperation(id: id); return true
    }
    func receivedNotification(operationID: String) {
        guard let operation = visibleOperations.first(where: { $0.remoteID == operationID || $0.id == operationID }) else { return }
        if active, (operation.state == .ready || operation.state == .failed), operation.completionPresentedAt == nil {
            banner = operation; markCompletionPresented(operation.id)
        }
    }
    private func markCompletionPresented(_ id: String) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].completionPresentedAt = Date(); persist()
    }
    func requestNotificationAuthorization() async {
        guard systemEnabled, completionAlertsEnabled else { return }
        do { notificationsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
        catch { AppLog.warning("Completion alert authorization failed", error: error, category: "operations") }
        if notificationsEnabled { UIApplication.shared.registerForRemoteNotifications() }
    }
    func refreshNotificationAuthorization() async {
        guard systemEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if notificationsEnabled { UIApplication.shared.registerForRemoteNotifications() }
    }
    private func notify(_ operation: AppOperation) {
        guard systemEnabled, completionAlertsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = operation.state == .ready ? String(localized: "Your operation is complete") : String(localized: "An operation needs attention")
        content.body = operation.title
        content.sound = .default
        content.userInfo = ["operationId": operation.id]
        Task {
            do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "operation-" + operation.id, content: content, trigger: nil)) }
            catch { AppLog.warning("Completion alert could not be scheduled", error: error, category: "operations") }
        }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(operations)
            try data.write(to: directory.appendingPathComponent("operations.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let discarded = try JSONEncoder().encode(discardedDraftDestinations)
            try discarded.write(to: directory.appendingPathComponent("discarded-drafts.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        } catch { AppLog.error("Operation history could not be saved", error: error, category: "operations") }
    }
}
