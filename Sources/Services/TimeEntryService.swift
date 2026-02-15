import Foundation
import SwiftData

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
