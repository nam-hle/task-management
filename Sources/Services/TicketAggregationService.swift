import Foundation

struct SourceDuration: Identifiable {
    let id = UUID()
    let pluginID: String
    let pluginDisplayName: String
    let duration: TimeInterval
    let entryCount: Int
}

struct TicketAggregate: Identifiable {
    let id: String
    let ticketID: String
    let totalDuration: TimeInterval
    let rawDuration: TimeInterval
    let entries: [TimeEntry]
    let sourceBreakdown: [SourceDuration]
}

enum TicketAggregationService {
    private static let pluginDisplayNames: [String: String] = [
        "wakatime": "Code",
        "chrome": "Chrome",
        "firefox": "Firefox",
    ]

    static func aggregate(entries: [TimeEntry]) -> [TicketAggregate] {
        // Group entries by ticketID (nil → "unassigned"), excluding excluded entries
        var groups: [String: [TimeEntry]] = [:]
        for entry in entries where !entry.isExcluded {
            let key = entry.ticketID ?? "unassigned"
            groups[key, default: []].append(entry)
        }

        var results: [TicketAggregate] = groups.map { ticketID, ticketEntries in
            let totalDuration = ticketEntries.reduce(0.0) {
                $0 + $1.effectiveDuration
            }
            let breakdown = sourceBreakdown(entries: ticketEntries)

            return TicketAggregate(
                id: ticketID,
                ticketID: ticketID,
                totalDuration: totalDuration,
                rawDuration: totalDuration,
                entries: ticketEntries.sorted { $0.startTime < $1.startTime },
                sourceBreakdown: breakdown
            )
        }

        // Sort: assigned tickets by duration descending, "unassigned" always last
        results.sort { a, b in
            if a.ticketID == "unassigned" { return false }
            if b.ticketID == "unassigned" { return true }
            return a.totalDuration > b.totalDuration
        }

        return results
    }

    static func totalDuration(entries: [TimeEntry]) -> TimeInterval {
        entries.filter { !$0.isExcluded }
            .reduce(0.0) { $0 + $1.effectiveDuration }
    }

    private static func sourceBreakdown(entries: [TimeEntry]) -> [SourceDuration] {
        var bySource: [String: (duration: TimeInterval, count: Int)] = [:]

        for entry in entries {
            let pluginID = entry.sourcePluginID ?? "unknown"
            let existing = bySource[pluginID] ?? (duration: 0, count: 0)
            bySource[pluginID] = (
                duration: existing.duration + entry.effectiveDuration,
                count: existing.count + 1
            )
        }

        return bySource.map { pluginID, info in
            SourceDuration(
                pluginID: pluginID,
                pluginDisplayName: pluginDisplayNames[pluginID] ?? pluginID,
                duration: info.duration,
                entryCount: info.count
            )
        }
        .sorted { $0.duration > $1.duration }
    }
}
