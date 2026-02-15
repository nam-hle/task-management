import SwiftUI
import SwiftData

struct TimeEntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntry.startTime, order: .forward)
    private var allEntries: [TimeEntry]

    @State private var selectedDate = Date()
    @State private var selectedEntries: Set<PersistentIdentifier> = []
    @State private var detailEntry: TimeEntry?
    @State private var errorMessage: String?

    private var entriesForDate: [TimeEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return allEntries.filter {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
    }

    private var dailyTotal: TimeInterval {
        entriesForDate.reduce(0.0) { $0 + $1.effectiveDuration }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if entriesForDate.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .sheet(item: $detailEntry) { entry in
            TimeEntryDetailView(
                entry: entry,
                onSave: { changes in
                    saveChanges(for: entry, changes: changes)
                },
                onSplit: { splitTime in
                    splitEntry(entry, at: splitTime)
                }
            )
        }
        .alert(
            "Error",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Entries")
                    .font(.headline)
                Text(formatDuration(dailyTotal))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .onChange(of: selectedDate) {
                selectedEntries.removeAll()
            }
        }
        .padding()
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            List(selection: $selectedEntries) {
                ForEach(entriesForDate) { entry in
                    TimeEntryRow(entry: entry)
                        .tag(entry.persistentModelID)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            detailEntry = entry
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("\(entriesForDate.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if selectedEntries.count >= 2 {
                Button {
                    mergeSelected()
                } label: {
                    Label("Merge Selected", systemImage: "arrow.triangle.merge")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                markSelectedReviewed()
            } label: {
                Label("Mark Reviewed", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedEntries.isEmpty)

            Button {
                markAllReviewed()
            } label: {
                Label("Mark All Reviewed", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No entries for this date")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func mergeSelected() {
        let ids = Array(selectedEntries)
        let service = TimeEntryService(modelContainer: modelContext.container)
        Task {
            do {
                _ = try await service.merge(entryIDs: ids)
                selectedEntries.removeAll()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markSelectedReviewed() {
        let ids = Array(selectedEntries)
        let entriesToLearn = entriesForDate.filter {
            ids.contains($0.persistentModelID)
                && $0.todo != nil
                && $0.applicationBundleID != nil
        }
        let service = TimeEntryService(modelContainer: modelContext.container)
        let patternService = LearnedPatternService(
            modelContainer: modelContext.container
        )
        Task {
            do {
                try await service.markReviewed(entryIDs: ids)

                // Learn from review
                for entry in entriesToLearn {
                    if let bundleID = entry.applicationBundleID,
                       let todoID = entry.todo?.persistentModelID {
                        try await patternService.learnFromReview(
                            contextType: "bundleID",
                            identifier: bundleID,
                            todoID: todoID
                        )
                    }
                }

                selectedEntries.removeAll()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markAllReviewed() {
        let ids = entriesForDate.map(\.persistentModelID)
        let service = TimeEntryService(modelContainer: modelContext.container)
        Task {
            do {
                try await service.markReviewed(entryIDs: ids)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveChanges(for entry: TimeEntry, changes: TimeEntryChanges) {
        let entryID = entry.persistentModelID
        let service = TimeEntryService(modelContainer: modelContext.container)
        Task {
            do {
                try await service.update(entryID: entryID, changes: changes)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func splitEntry(_ entry: TimeEntry, at splitTime: Date) {
        let entryID = entry.persistentModelID
        let service = TimeEntryService(modelContainer: modelContext.container)
        Task {
            do {
                _ = try await service.split(entryID: entryID, at: splitTime)
                detailEntry = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
