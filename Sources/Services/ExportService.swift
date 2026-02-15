import Foundation
import SwiftData

struct ExportResult {
    let formattedText: String
    let entryIDs: [UUID]
    let totalDuration: TimeInterval
}

@ModelActor
actor ExportService {
    func generateExport(for date: Date) throws -> ExportResult {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let reviewedStatus = BookingStatus.reviewed
        let predicate = #Predicate<TimeEntry> {
            $0.startTime >= startOfDay
                && $0.startTime < endOfDay
                && $0.bookingStatus == reviewedStatus
        }
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        let entries = try modelContext.fetch(descriptor)

        guard !entries.isEmpty else {
            return ExportResult(
                formattedText: "No reviewed entries for \(formatDate(date)).",
                entryIDs: [],
                totalDuration: 0
            )
        }

        // Group by: todo title > app name > label
        var groups: [(key: String, duration: TimeInterval)] = []
        var grouped: [String: TimeInterval] = [:]

        for entry in entries {
            let key: String
            if let todo = entry.todo {
                key = todo.title
            } else if let appName = entry.applicationName {
                key = appName
            } else if let label = entry.label {
                key = label
            } else {
                key = "Other"
            }
            grouped[key, default: 0] += entry.duration
        }

        groups = grouped
            .sorted { $0.value > $1.value }
            .map { (key: $0.key, duration: $0.value) }

        let totalDuration = entries.reduce(0.0) { $0 + $1.duration }

        // Format output
        var lines: [String] = []
        lines.append("Time Report: \(formatDate(date))")
        lines.append(String(repeating: "─", count: 40))
        lines.append("")

        for group in groups {
            let formatted = formatDuration(group.duration)
            lines.append("  \(formatted)  \(group.key)")
        }

        lines.append("")
        lines.append(String(repeating: "─", count: 40))
        lines.append("  \(formatDuration(totalDuration))  Total")

        let formattedText = lines.joined(separator: "\n")
        let entryIDs = entries.map(\.id)

        return ExportResult(
            formattedText: formattedText,
            entryIDs: entryIDs,
            totalDuration: totalDuration
        )
    }

    func checkDuplicates(entryIDs: [UUID]) throws -> [UUID] {
        let exportedStatus = BookingStatus.exported
        let bookedStatus = BookingStatus.booked
        let predicate = #Predicate<TimeEntry> {
            $0.bookingStatus == exportedStatus || $0.bookingStatus == bookedStatus
        }
        let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate)
        let exportedEntries = try modelContext.fetch(descriptor)
        let exportedIDs = Set(exportedEntries.map(\.id))
        return entryIDs.filter { exportedIDs.contains($0) }
    }

    func confirmExport(result: ExportResult) throws -> PersistentIdentifier {
        let record = ExportRecord(
            formattedOutput: result.formattedText,
            entryCount: result.entryIDs.count,
            totalDuration: result.totalDuration,
            timeEntryIDs: result.entryIDs
        )
        modelContext.insert(record)

        // Transition entries to exported
        for entryID in result.entryIDs {
            let predicate = #Predicate<TimeEntry> { $0.id == entryID }
            let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate)
            if let entry = try modelContext.fetch(descriptor).first {
                entry.bookingStatus = .exported
            }
        }

        try modelContext.save()
        return record.persistentModelID
    }

    func markBooked(exportID: PersistentIdentifier) throws {
        guard let record = modelContext.model(for: exportID) as? ExportRecord else {
            return
        }
        record.isBooked = true
        record.bookedAt = Date()

        for entryID in record.timeEntryIDs {
            let predicate = #Predicate<TimeEntry> { $0.id == entryID }
            let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate)
            if let entry = try modelContext.fetch(descriptor).first {
                entry.bookingStatus = .booked
            }
        }

        try modelContext.save()
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
