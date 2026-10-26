import os

/// Public log entries contain only app state and action names, never typed
/// text, window titles, file names, or touch positions.
enum Diagnostic {
    private static let logger = Logger(subsystem: "com.local.ontouch", category: "status")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
