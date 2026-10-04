import ActivityKit
import Foundation

@MainActor
final class OperationLiveActivities {
    private let cloud: CloudNarrationModel
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    init(cloud: CloudNarrationModel) { self.cloud = cloud }

    func start(_ operation: AppOperation) {
        guard let remoteID = operation.remoteID, operation.isActive, ActivityAuthorizationInfo().areActivitiesEnabled,
              !Activity<OperationActivityAttributes>.activities.contains(where: { $0.attributes.operationID == remoteID }) else { return }
        do {
            let activity = try Activity.request(attributes: OperationActivityAttributes(operationID: remoteID),
                content: ActivityContent(state: content(operation), staleDate: Date().addingTimeInterval(300)), pushType: .token)
            observeToken(activity, operation: operation)
        } catch { AppLog.warning("Operation Live Activity could not start", error: error, category: "operations") }
    }
    func restore(_ operations: [AppOperation]) {
        for activity in Activity<OperationActivityAttributes>.activities {
            if let operation = operations.first(where: { $0.remoteID == activity.attributes.operationID }) { observeToken(activity, operation: operation); update(operation) }
            else { Self.finish(remoteID: activity.attributes.operationID) }
        }
        for operation in operations where operation.remoteID != nil { start(operation) }
    }
    func refreshRegistrations(_ operations: [AppOperation]) {
        for activity in Activity<OperationActivityAttributes>.activities {
            guard let token = activity.pushToken,
                  let operation = operations.first(where: { $0.remoteID == activity.attributes.operationID }) else { continue }
            Task {
                await register(operation: operation, token: token)
            }
        }
    }
    private func observeToken(_ activity: Activity<OperationActivityAttributes>, operation: AppOperation) {
        let key = operation.remoteID ?? operation.id
        guard tokenTasks[key] == nil else { return }
        tokenTasks[key] = Task {
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled, cloud.userID == operation.ownerID else { break }
                await register(operation: operation, token: token)
            }
        }
    }
    private func register(operation: AppOperation, token: Data) async {
        for attempt in 0..<4 {
            guard !Task.isCancelled, cloud.userID == operation.ownerID else { return }
            do {
                try await cloud.registerActivity(operation: operation, token: token.map { String(format: "%02x", $0) }.joined())
                return
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.warning("Live Activity registration attempt failed", error: error, category: "operations", metadata: ["attempt": .integer(attempt + 1)])
                if attempt < 3 {
                    do { try await Task.sleep(for: .seconds(2 << attempt)) }
                    catch { return }
                }
            }
        }
    }
    func update(_ operation: AppOperation) {
        guard let remoteID = operation.remoteID else { return }
        let next = ActivityContent(state: content(operation), staleDate: Date().addingTimeInterval(300))
        let active = operation.isActive
        Task.detached {
            // Resolve inside this task rather than sending ActivityKit's non-Sendable
            // reference from the main actor across an async SDK call.
            for activity in Activity<OperationActivityAttributes>.activities where activity.attributes.operationID == remoteID {
                if active { await activity.update(next) }
                else { await activity.end(next, dismissalPolicy: .after(Date().addingTimeInterval(60))) }
            }
        }
        if !operation.isActive { tokenTasks.removeValue(forKey: operation.remoteID ?? operation.id)?.cancel() }
    }
    func end(_ operation: AppOperation) {
        tokenTasks.removeValue(forKey: operation.remoteID ?? operation.id)?.cancel()
        if let remoteID = operation.remoteID { Self.finish(remoteID: remoteID) }
    }
    nonisolated private static func finish(remoteID: String) {
        Task.detached {
            for activity in Activity<OperationActivityAttributes>.activities where activity.attributes.operationID == remoteID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    private func content(_ operation: AppOperation) -> OperationActivityAttributes.ContentState {
        // Match the server schema; private book titles stay inside the app.
        .init(operationID: operation.remoteID ?? operation.id,
              title: operation.kind == .voiceEnrollment ? String(localized: "Creating your voice") : operation.kind == .storyGeneration ? String(localized: "Writing your story") : String(localized: "Creating narration"),
              subtitle: operation.subtitle, progress: operation.progress ?? 0, state: operation.state.rawValue)
    }
}
