import Foundation

// MARK: - Duration Formatting

extension TimeInterval {
    /// Formats as `"3h 05m"` — fixed hours + zero-padded minutes.
    var hoursMinutes: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    /// Formats as `"3h 05m 02s"` or `"5m 02s"` when under an hour.
    var hoursMinutesSeconds: String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    /// Formats as `"5m 30s"`, `"5m"`, or `"30s"` — omits zero components.
    var settingsDuration: String {
        let mins = Int(self) / 60
        let secs = Int(self) % 60
        if mins > 0 && secs > 0 {
            return "\(mins)m \(secs)s"
        } else if mins > 0 {
            return "\(mins)m"
        }
        return "\(Int(self))s"
    }
}

// MARK: - Shared DateFormatters

enum Formatters {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static func timeRange(start: Date, end: Date?) -> String {
        let startText = shortTime.string(from: start)
        if let end {
            return "\(startText) – \(shortTime.string(from: end))"
        }
        return "\(startText) – now"
    }
}
