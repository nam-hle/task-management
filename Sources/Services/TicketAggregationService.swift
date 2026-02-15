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
            let rawDuration = ticketEntries.reduce(0.0) { $0 + $1.effectiveDuration }
            let dedupDuration = deduplicatedDuration(entries: ticketEntries)
            let breakdown = sourceBreakdown(entries: ticketEntries)

            return TicketAggregate(
                id: ticketID,
                ticketID: ticketID,
                totalDuration: dedupDuration,
                rawDuration: rawDuration,
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

    static func deduplicatedDuration(entries: [TimeEntry]) -> TimeInterval {
        let intervals: [(start: Date, end: Date)] = entries.compactMap { entry in
            let end = entry.endTime ?? Date()
            guard end > entry.startTime else { return nil }
            return (start: entry.startTime, end: end)
        }
        let merged = mergeIntervals(intervals)
        return merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    static func mergeIntervals(
        _ intervals: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }

        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = [sorted[0]]

        for interval in sorted.dropFirst() {
            if interval.start <= merged[merged.count - 1].end {
                // Overlapping — extend the end
                let newEnd = max(merged[merged.count - 1].end, interval.end)
                merged[merged.count - 1] = (start: merged[merged.count - 1].start, end: newEnd)
            } else {
                merged.append(interval)
            }
        }

        return merged
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
