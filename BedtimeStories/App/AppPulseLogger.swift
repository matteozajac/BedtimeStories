import CoreData
import Foundation
import MZAppFoundation
import OSLog
import Pulse

/// Preserve Pulse's normal session/event path without blocking its UI context.
/// Foundation 0.5.0's synchronous metadata repair can deadlock an open console.
@MainActor final class AppPulseLogger: AppLogging {
    private let store: LoggerStore
    private let redaction: RedactionPolicy

    init(store: LoggerStore = .shared, redaction: RedactionPolicy = .init()) {
        self.store = store; self.redaction = redaction
    }

    func log(_ entry: LogEntry) {
        let entry = redaction.sanitize(entry)
        let level: LoggerStore.Level = switch entry.level {
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        }
        var metadata = entry.metadata.mapValues { $0.rendered }
        if let error = entry.error {
            for (index, cause) in error.causes.enumerated() {
                let prefix = "error.cause.\(index)"
                metadata[prefix + ".type"] = cause.type
                metadata[prefix + ".domain"] = cause.domain
                metadata[prefix + ".code"] = String(cause.code)
                metadata[prefix + ".message"] = cause.message
            }
            metadata["error.stack"] = error.stack.origin.rawValue
            for (index, symbol) in error.stack.symbols.enumerated() {
                metadata[String(format: "error.stack.%02d", index)] = symbol
            }
        }
        let needsCorrection = metadata.values.contains { $0.contains(where: \.isWhitespace) }
        let marker = UUID().uuidString
        var stored = metadata
        if needsCorrection { stored["mz_record_id"] = marker }
        store.storeMessage(label: entry.category, level: level, message: entry.message,
                           metadata: stored.mapValues { .string($0) }, file: entry.source.file,
                           function: entry.source.function, line: entry.source.line)
        guard needsCorrection else { return }
        let preserved = metadata.sorted { $0.key < $1.key }.map { key, value in
            let key = key.replacingOccurrences(of: ":", with: "").components(separatedBy: .newlines).joined()
            let value = value.components(separatedBy: .newlines).joined(separator: " ")
            return "\(key): \(value)"
        }.joined(separator: "\n")
        let context = store.backgroundContext
        // FIFO on the write context keeps insertion before repair. The main
        // thread must remain free for fetched-results save notifications.
        context.perform {
            do {
                let request = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
                request.predicate = NSPredicate(format: "rawMetadata CONTAINS %@", "mz_record_id: " + marker)
                request.fetchLimit = 1
                guard let message = try context.fetch(request).first else { return }
                message.rawMetadata = preserved
                try context.save()
            } catch {
                Logger(subsystem: "BedtimeStories", category: "Pulse").error("Unable to preserve diagnostic metadata formatting")
            }
        }
    }

    /// Async write-queue barrier for diagnostics verification; never blocks UI.
    func flush() async {
        await store.backgroundContext.perform { }
    }
}
