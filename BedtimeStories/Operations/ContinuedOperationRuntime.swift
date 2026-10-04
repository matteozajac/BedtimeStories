import BackgroundTasks
import UIKit

/// Runs user initiated local work under the system's continued-processing UI.
@MainActor
final class ContinuedOperationRuntime {
    private var continued: [String: BGContinuedProcessingTask] = [:]
    private var fallbacks: [String: UIBackgroundTaskIdentifier] = [:]
    private var finished: [String: Bool] = [:]
    private var identifiers: [String: String] = [:]

    func begin(id: String, title: String, subtitle: String, expired: @escaping @MainActor () -> Void) {
        guard identifiers[id] == nil else { return }
        let identifier = (Bundle.main.bundleIdentifier ?? "com.matteozajac.bedtimestories") + ".operation." + UUID().uuidString
        identifiers[id] = identifier
        let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                if let result = self.finished[identifier] { task.setTaskCompleted(success: result); return }
                self.endFallback(id)
                task.progress.totalUnitCount = 100
                task.expirationHandler = { Task { @MainActor in expired() } }
                self.continued[id] = task
            }
        }
        guard success else { fallback(id: id, expired: expired); return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        Task {
            do { try await BGTaskScheduler.shared.submitTaskRequest(request) }
            catch {
                guard finished[identifier] == nil else { return }
                AppLog.warning("Continued background processing unavailable", error: error, category: "operations")
                fallback(id: id, expired: expired)
            }
        }
    }

    func update(id: String, progress: Double?, title: String, subtitle: String) {
        guard let task = continued[id] else { return }
        if let progress { task.progress.completedUnitCount = Int64(min(1, max(0, progress)) * 100) }
        task.updateTitle(title, subtitle: subtitle)
    }

    func end(id: String, success: Bool) {
        if let identifier = identifiers.removeValue(forKey: id) {
            finished[identifier] = success
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        if let task = continued.removeValue(forKey: id) {
            task.progress.completedUnitCount = success ? 100 : task.progress.completedUnitCount
            task.setTaskCompleted(success: success)
        }
        endFallback(id)
    }

    private func fallback(id: String, expired: @escaping @MainActor () -> Void) {
        fallbacks[id] = UIApplication.shared.beginBackgroundTask(withName: "Story operation") { Task { @MainActor in expired() } }
    }
    private func endFallback(_ id: String) {
        if let task = fallbacks.removeValue(forKey: id), task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }
}
