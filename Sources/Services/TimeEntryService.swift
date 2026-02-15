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
        source: EntrySource = .autoDetected,
        startTime: Date = Date(),
        label: String? = nil
    ) throws -> PersistentIdentifier {
        let entry = TimeEntry(
            startTime: startTime,
            source: source,
            isInProgress: true,
            applicationName: applicationName,
            applicationBundleID: applicationBundleID,
            label: label
        )
        if let todoID, let todo = modelContext.model(for: todoID) as? Todo {
            entry.todo = todo
        }
        modelContext.insert(entry)
        try modelContext.save()
        return entry.persistentModelID
    }

    func finalize(entryID: PersistentIdentifier, endTime: Date = Date()) throws {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry else { return }
        entry.endTime = endTime
        entry.duration = endTime.timeIntervalSince(entry.startTime)
        entry.isInProgress = false
        try modelContext.save()
    }

    func autoSave(entryID: PersistentIdentifier, currentTime: Date = Date()) throws {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry,
              entry.isInProgress else { return }
        entry.duration = currentTime.timeIntervalSince(entry.startTime)
        try modelContext.save()
    }

    func splitAtMidnight(entryID: PersistentIdentifier) throws -> PersistentIdentifier? {
        guard let entry = modelContext.model(for: entryID) as? TimeEntry else { return nil }

        let calendar = Calendar.current
        let startOfNextDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: entry.startTime)!
        )

        let endTime = entry.endTime ?? Date()

        // Only split if entry crosses midnight
        guard endTime > startOfNextDay else { return nil }

        // Finalize first part at midnight
        entry.endTime = startOfNextDay
        entry.duration = startOfNextDay.timeIntervalSince(entry.startTime)
        entry.isInProgress = false

        // Create second part starting at midnight
        let newEntry = TimeEntry(
            startTime: startOfNextDay,
            endTime: entry.isInProgress ? nil : endTime,
            duration: endTime.timeIntervalSince(startOfNextDay),
            source: entry.source,
            isInProgress: entry.isInProgress,
            todo: entry.todo,
            applicationName: entry.applicationName,
            applicationBundleID: entry.applicationBundleID,
            label: entry.label
        )
        newEntry.bookingStatus = entry.bookingStatus
        modelContext.insert(newEntry)
        try modelContext.save()
        return newEntry.persistentModelID
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

    // MARK: - Auto-Approval (Phase 8)

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

    // MARK: - Seeding

    func seedTrackedApplicationsIfNeeded() throws {
        let descriptor = FetchDescriptor<TrackedApplication>()
        let existing = try modelContext.fetch(descriptor)
        guard existing.isEmpty else { return }

        let preConfigured: [(String, String, Bool)] = [
            ("Google Chrome", "com.google.Chrome", true),
            ("Firefox", "org.mozilla.firefox", true),
        ]
        let suggested: [(String, String)] = [
            ("IntelliJ IDEA", "com.jetbrains.intellij"),
            ("Xcode", "com.apple.dt.Xcode"),
            ("Visual Studio Code", "com.microsoft.VSCode"),
            ("Terminal", "com.apple.Terminal"),
            ("Slack", "com.tinyspeck.slackmacgap"),
        ]

        for (index, (name, bundleID, isBrowser)) in preConfigured.enumerated() {
            let app = TrackedApplication(
                name: name,
                bundleIdentifier: bundleID,
                isBrowser: isBrowser,
                isPreConfigured: true,
                isEnabled: true,
                sortOrder: index
            )
            modelContext.insert(app)
        }

        for (index, (name, bundleID)) in suggested.enumerated() {
            let app = TrackedApplication(
                name: name,
                bundleIdentifier: bundleID,
                isBrowser: false,
                isPreConfigured: false,
                isEnabled: false,
                sortOrder: preConfigured.count + index
            )
            modelContext.insert(app)
        }

        try modelContext.save()
    }
}
