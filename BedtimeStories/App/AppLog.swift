import MZAppFoundation

/// App-owned entry point for technical logs. Feature models can inject another sink.
@MainActor
enum AppLog {
    static var logger: any AppLogging = RecordingLogger()

    static func trace(_ message: String, category: String,
                      metadata: [String: TelemetryValue] = [:],
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.trace(message, category: category, metadata: metadata,
                     file: file, function: function, line: line)
    }

    static func debug(_ message: String, category: String,
                      metadata: [String: TelemetryValue] = [:],
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.debug(message, category: category, metadata: metadata,
                     file: file, function: function, line: line)
    }

    static func info(_ message: String, category: String,
                     metadata: [String: TelemetryValue] = [:],
                     file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.log(LogEntry(message, category: category, metadata: metadata,
                            file: file, function: function, line: line))
    }

    static func warning(_ message: String, error: (any Error)? = nil, category: String,
                        metadata: [String: TelemetryValue] = [:],
                        file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.warning(message, error: error, category: category, metadata: metadata,
                       file: file, function: function, line: line)
    }

    static func error(_ message: String, error: any Error, category: String,
                      metadata: [String: TelemetryValue] = [:],
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.error(message, error: error, category: category, metadata: metadata,
                     file: file, function: function, line: line)
    }

    static func error(_ message: String, category: String,
                      metadata: [String: TelemetryValue] = [:],
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.error(message, category: category, metadata: metadata,
                     file: file, function: function, line: line)
    }
}

/// Foundation 0.5.0 stores trace entries at debug level. The verbosity field
/// distinguishes detailed connection progress in Pulse without filtering it out.
extension AppLogging {
    func trace(_ message: String, category: String,
               metadata: [String: TelemetryValue] = [:],
               file: String = #fileID, function: String = #function, line: UInt = #line) {
        var fields = metadata
        fields["verbosity"] = .string("trace")
        log(LogEntry(message, level: .debug, category: category, metadata: fields,
                     file: file, function: function, line: line))
    }

    func debug(_ message: String, category: String,
               metadata: [String: TelemetryValue] = [:],
               file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(LogEntry(message, level: .debug, category: category, metadata: metadata,
                     file: file, function: function, line: line))
    }

    func warning(_ message: String, error: (any Error)? = nil, category: String,
                 metadata: [String: TelemetryValue] = [:],
                 file: String = #fileID, function: String = #function, line: UInt = #line) {
        if let error, ErrorSnapshot.isCancellation(error) {
            trace(message, category: category, metadata: metadata.merging(["cancelled": .bool(true)]) { _, new in new },
                  file: file, function: function, line: line)
            return
        }
        let snapshot = error.map { ErrorSnapshot($0, file: file, function: function, line: line) }
        log(LogEntry(message, level: .warning, category: category, metadata: metadata, error: snapshot,
                     file: file, function: function, line: line))
    }
}

/// File actors capture evidence on their own executor and deliver in operation order.
/// The logger itself remains on the main actor as required by Foundation.
nonisolated struct FeatureLogBuffer {
    let destination: FeatureLogDestination?
    private var delivery: Task<Void, Never>?

    init(destination: FeatureLogDestination?) { self.destination = destination }

    mutating func trace(_ message: String, category: String,
                        metadata: [String: TelemetryValue] = [:],
                        file: String = #fileID, function: String = #function, line: UInt = #line) {
        let fields = metadata.merging(["verbosity": .string("trace")]) { _, new in new }
        append(LogEntry(message, level: .debug, category: category, metadata: fields,
                        file: file, function: function, line: line))
    }

    mutating func warning(_ message: String, error: (any Error)? = nil, category: String,
                          metadata: [String: TelemetryValue] = [:],
                          file: String = #fileID, function: String = #function, line: UInt = #line) {
        if let error, ErrorSnapshot.isCancellation(error) {
            trace(message, category: category, metadata: metadata.merging(["cancelled": .bool(true)]) { _, new in new },
                  file: file, function: function, line: line)
            return
        }
        let snapshot = error.map { ErrorSnapshot($0, file: file, function: function, line: line) }
        append(LogEntry(message, level: .warning, category: category, metadata: metadata, error: snapshot,
                        file: file, function: function, line: line))
    }

    private mutating func append(_ entry: LogEntry) {
        let previous = delivery
        let destination = destination
        delivery = Task { @MainActor in
            await previous?.value
            (destination?.logger ?? AppLog.logger).log(entry)
        }
    }

    func flush() async { await delivery?.value }
}

/// Global-actor-isolated references can safely cross file actor boundaries.
@MainActor final class FeatureLogDestination {
    let logger: any AppLogging
    init(logger: any AppLogging) { self.logger = logger }
}
