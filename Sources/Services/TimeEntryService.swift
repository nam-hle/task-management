import Foundation
import SwiftData

enum TimeEntryServiceError: Error, LocalizedError {
    case entryNotFound
    case insufficientEntries
    case invalidSplitTime

    var errorDescription: String? {
        switch self {
        case .entryNotFound: "Time entry not found"
        case .insufficientEntries: "Need at least 2 entries to merge"
        case .invalidSplitTime: "Split time must be between entry start and end"
        }
    }
}

@ModelActor
actor TimeEntryService {
    func create(
        todoID: PersistentIdentifier? = nil,
        applicationName: String? = nil,
        applicationBundleID: String? = nil,
        source: EntrySource = .manual,
        startTime: Date = Date(),
        label: String? = nil,
        sourcePluginID: String? = nil,
        ticketID: String? = nil,
        contextMetadata: String? = nil
    ) throws -> PersistentIdentifier {
        let entry = TimeEntry(
            startTime: startTime,
            source: source,
            isInProgress: true,
            applicationName: applicationName,
            applicationBundleID: applicationBundleID,
            label: label,
            sourcePluginID: sourcePluginID,
            ticketID: ticketID,
            contextMetadata: contextMetadata
        )
        if let todoID, let todo = modelContext.model(for: todoID) as? Todo {
            entry.todo = todo
        }
        modelContext.insert(entry)
        try modelContext.save()
        checkAutoApproval(for: entry)
        return entry.persistentModelID
    }

    func createFinalized(
        startTime: Date,
        endTime: Date,
        source: EntrySource,
        applicationName: String? = nil,
        sourcePluginID: String? = nil,
        ticketID: String? = nil,
        contextMetadata: String? = nil
    ) throws -> PersistentIdentifier {
        let duration = endTime.timeIntervalSince(startTime)
        guard duration > 0 else { return try create(startTime: startTime) }
        let entry = TimeEntry(
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            source: source,
            isInProgress: false,
            applicationName: applicationName,
            sourcePluginID: sourcePluginID,
            ticketID: ticketID,
            contextMetadata: contextMetadata
        )
        modelContext.insert(entry)
        try modelContext.save()
        checkAutoApproval(for: entry)
        return entry.persistentModelID
    }

    func finalize(entryID: PersistentIdentifier, endTime: Date = Date()) throws {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry else { return }
        entry.endTime = endTime
        entry.duration = endTime.timeIntervalSince(entry.startTime)
        entry.isInProgress = false
        try modelContext.save()
    }

    func entries(for date: Date) throws -> [TimeEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<TimeEntry> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func inProgressEntries() throws -> [TimeEntry] {
        let predicate = #Predicate<TimeEntry> { $0.isInProgress == true }
        let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    func recoverInProgressEntries() throws -> Int {
        let entries = try inProgressEntries()
        for entry in entries {
            let endTime = entry.endTime ?? Date()
            entry.endTime = endTime
            entry.duration = endTime.timeIntervalSince(entry.startTime)
            entry.isInProgress = false
        }
        if !entries.isEmpty {
            try modelContext.save()
        }
        return entries.count
    }

    // MARK: - Review & Edit (Phase 5)

    func merge(entryIDs: [PersistentIdentifier]) throws -> PersistentIdentifier {
        guard entryIDs.count >= 2 else {
            throw TimeEntryServiceError.insufficientEntries
        }

        let entries: [TimeEntry] = entryIDs.compactMap {
            modelContext.model(for: $0) as? TimeEntry
        }
        guard entries.count == entryIDs.count else {
            throw TimeEntryServiceError.entryNotFound
        }

        let sorted = entries.sorted { $0.startTime < $1.startTime }
        let earliestStart = sorted.first!.startTime
        let latestEnd = sorted.compactMap(\.endTime).max() ?? Date()
        let totalDuration = sorted.reduce(0.0) { $0 + $1.duration }
        let combinedNotes = sorted
            .map(\.notes)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let merged = TimeEntry(
            startTime: earliestStart,
            endTime: latestEnd,
            duration: totalDuration,
            notes: combinedNotes,
            bookingStatus: .unreviewed,
            source: .edited,
            isInProgress: false,
            todo: sorted.first?.todo,
            applicationName: sorted.first?.applicationName,
            applicationBundleID: sorted.first?.applicationBundleID,
            label: sorted.first?.label
        )
        modelContext.insert(merged)

        for entry in entries {
            modelContext.delete(entry)
        }
        try modelContext.save()
        return merged.persistentModelID
    }

    func split(
        entryID: PersistentIdentifier,
        at splitTime: Date
    ) throws -> (PersistentIdentifier, PersistentIdentifier) {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry else {
            throw TimeEntryServiceError.entryNotFound
        }
        let endTime = entry.endTime ?? Date()
        guard splitTime > entry.startTime && splitTime < endTime else {
            throw TimeEntryServiceError.invalidSplitTime
        }

        let secondEntry = TimeEntry(
            startTime: splitTime,
            endTime: endTime,
            duration: endTime.timeIntervalSince(splitTime),
            notes: entry.notes,
            bookingStatus: entry.bookingStatus,
            source: entry.source,
            isInProgress: false,
            todo: entry.todo,
            applicationName: entry.applicationName,
            applicationBundleID: entry.applicationBundleID,
            label: entry.label
        )
        modelContext.insert(secondEntry)

        entry.endTime = splitTime
        entry.duration = splitTime.timeIntervalSince(entry.startTime)
        entry.isInProgress = false

        try modelContext.save()
        return (entry.persistentModelID, secondEntry.persistentModelID)
    }

    func update(entryID: PersistentIdentifier, changes: TimeEntryChanges) throws {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry else {
            throw TimeEntryServiceError.entryNotFound
        }

        var timesChanged = false

        if let newStart = changes.startTime, newStart != entry.startTime {
            entry.startTime = newStart
            timesChanged = true
        }
        if let newEnd = changes.endTime, newEnd != entry.endTime {
            entry.endTime = newEnd
            timesChanged = true
        }
        if timesChanged, let end = entry.endTime {
            entry.duration = end.timeIntervalSince(entry.startTime)
            entry.source = .edited
        }

        if let newNotes = changes.notes {
            entry.notes = newNotes
        }
        if changes.removeTodo {
            entry.todo = nil
        } else if let todoID = changes.todoID,
                  let todo = modelContext.model(for: todoID) as? Todo {
            entry.todo = todo
        }
        if let newStatus = changes.bookingStatus {
            entry.bookingStatus = newStatus
        }
        if changes.removeTicketID {
            entry.ticketID = nil
        } else if let newTicketID = changes.ticketID {
            entry.ticketID = newTicketID
        }

        try modelContext.save()
    }

    func markReviewed(entryIDs: [PersistentIdentifier]) throws {
        for entryID in entryIDs {
            guard let entry = modelContext.model(for: entryID) as? TimeEntry else {
                continue
            }
            if entry.bookingStatus == .unreviewed {
                entry.bookingStatus = .reviewed
            }
        }
        try modelContext.save()
    }

    func assignTicket(
        entryIDs: [PersistentIdentifier],
        ticketID: String
    ) throws {
        for entryID in entryIDs {
            guard let entry = modelContext.model(for: entryID) as? TimeEntry else {
                continue
            }
            entry.ticketID = ticketID
        }
        try modelContext.save()
    }

    // MARK: - Auto-Approval (Phase 8)

    private func checkAutoApproval(for entry: TimeEntry) {
        guard let bundleID = entry.applicationBundleID else { return }

        let contextType = "bundleID"
        let predicate = #Predicate<LearnedPattern> {
            $0.contextType == contextType
                && $0.identifierValue == bundleID
                && $0.isActive == true
        }
        let descriptor = FetchDescriptor<LearnedPattern>(predicate: predicate)
        guard let pattern = try? modelContext.fetch(descriptor).first,
              let todo = pattern.linkedTodo else { return }

        entry.isAutoApproved = true
        entry.learnedPattern = pattern
        entry.todo = todo
        entry.bookingStatus = .reviewed
        try? modelContext.save()
    }

    func applyAutoApproval(
        entryID: PersistentIdentifier,
        patternID: PersistentIdentifier,
        todoID: PersistentIdentifier
    ) throws {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry else { return }
        if let todo = modelContext.model(for: todoID) as? Todo {
            entry.todo = todo
        }
        if let pattern = modelContext.model(for: patternID) as? LearnedPattern {
            entry.learnedPattern = pattern
        }
        entry.isAutoApproved = true
        entry.bookingStatus = .reviewed
        try modelContext.save()
    }

    // MARK: - Data Retention (Phase 9)

    func purgeExpired(retentionDays: Int = 90) throws -> Int {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -retentionDays, to: Date()
        )!

        let bookedStatus = BookingStatus.booked
        let predicate = #Predicate<TimeEntry> {
            $0.bookingStatus == bookedStatus && $0.startTime < cutoff
        }
        let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate)
        let expiredEntries = try modelContext.fetch(descriptor)

        let exportPredicate = #Predicate<ExportRecord> {
            $0.exportedAt < cutoff && $0.isBooked == true
        }
        let exportDescriptor = FetchDescriptor<ExportRecord>(predicate: exportPredicate)
        let expiredExports = try modelContext.fetch(exportDescriptor)

        let count = expiredEntries.count + expiredExports.count
        for entry in expiredEntries {
            modelContext.delete(entry)
        }
        for export in expiredExports {
            modelContext.delete(export)
        }

        if count > 0 {
            try modelContext.save()
        }
        return count
    }

    func deleteAll() throws {
        let descriptor = FetchDescriptor<TimeEntry>()
        let entries = try modelContext.fetch(descriptor)
        for entry in entries {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }

}
