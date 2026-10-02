import MZAppFoundation

/// App-owned entry point for technical logs. Feature models can inject another sink.
@MainActor
enum AppLog {
    static var logger: any AppLogging = RecordingLogger()

    static func info(_ message: String, category: String,
                     metadata: [String: TelemetryValue] = [:],
                     file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.log(LogEntry(message, category: category, metadata: metadata,
                            file: file, function: function, line: line))
    }

    static func error(_ message: String, error: any Error, category: String,
                      metadata: [String: TelemetryValue] = [:],
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        logger.error(message, error: error, category: category, metadata: metadata,
                     file: file, function: function, line: line)
    }
}
