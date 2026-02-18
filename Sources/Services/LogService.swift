import SwiftUI

enum LogLevel: String {
    case info = "INFO"
    case error = "ERROR"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel
}

@MainActor @Observable
final class LogService {
    private(set) var entries: [LogEntry] = []
    private var maxEntries: Int { AppConfig.maxLogEntries }

    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        print("[\(level.rawValue)] \(message)")
    }
}

// MARK: - Environment Key

private struct LogServiceKey: EnvironmentKey {
    static let defaultValue: LogService? = nil
}

extension EnvironmentValues {
    var logService: LogService? {
        get { self[LogServiceKey.self] }
        set { self[LogServiceKey.self] = newValue }
    }
}
