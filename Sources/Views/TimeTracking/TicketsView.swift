import SwiftUI
import SwiftData

struct TicketsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntry.startTime, order: .reverse)
    private var allEntries: [TimeEntry]

    @State private var selectedDate = Date()
    @State private var showSettings = false
    @State private var refreshTick = 0

    @AppStorage("ticketExcludedProjects") private var excludedProjectsData = Data()
    @AppStorage("ticketUnknownPatterns") private var unknownPatternsData = Data()

    private var entriesForDate: [TimeEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return allEntries.filter {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
                && !$0.isExcluded
        }
    }

    private var tickets: [TicketAggregate] {
        _ = refreshTick
        return TicketAggregationService.aggregate(entries: entriesForDate)
    }

    private var assignedTickets: [TicketAggregate] {
        tickets.filter { $0.ticketID != "unassigned" }
    }

    private var unassignedTicket: TicketAggregate? {
        tickets.first { $0.ticketID == "unassigned" }
    }

    private var hasInProgressEntries: Bool {
        entriesForDate.contains { $0.isInProgress }
    }

    private var totalDuration: TimeInterval {
        _ = refreshTick
        return TicketAggregationService.deduplicatedDuration(entries: entriesForDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showSettings) {
            TicketSettingsView(
                excludedProjectsData: $excludedProjectsData,
                unknownPatternsData: $unknownPatternsData
            )
        }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            if hasInProgressEntries {
                refreshTick &+= 1
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(assignedTickets.count) tickets")
                    .font(.headline)
                Text(formatDuration(totalDuration))
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

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Ticket settings")
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if entriesForDate.isEmpty {
            emptyState
        } else {
            dataView
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No ticket activity")
                .foregroundStyle(.secondary)
            Text("Time entries will appear here as plugins track your activity")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data View

    private var dataView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ticketTimeline
                    .padding(.top, 8)

                Divider()

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(assignedTickets) { ticket in
                        TicketDetailView(ticket: ticket)
                    }

                    if let unassigned = unassignedTicket {
                        Divider()
                        UnassignedTimeView(entries: unassigned.entries)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Timeline

    private var ticketTimeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(assignedTickets.prefix(10).enumerated()), id: \.element.id) {
                index, ticket in
                let color = ticketColors[index % ticketColors.count]
                ticketTimelineRow(ticket: ticket, color: color)

                if index < min(assignedTickets.count, 10) - 1 {
                    Divider().opacity(0.5)
                }
            }

            if let unassigned = unassignedTicket {
                Divider().opacity(0.5)
                ticketTimelineRow(ticket: unassigned, color: .gray)
            }
        }
    }

    private func ticketTimelineRow(
        ticket: TicketAggregate, color: Color
    ) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(ticket.ticketID == "unassigned"
                    ? "Unassigned" : ticket.ticketID)
                    .font(.callout.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(ticket.ticketID == "unassigned"
                        ? .secondary : .primary)
                    .jiraHoverPopover(ticketID: ticket.ticketID)
                Text(formatDuration(ticket.totalDuration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 200)
            .padding(.leading, 8)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary.opacity(0.3))
                        .frame(height: 14)

                    ForEach(ticket.entries) { entry in
                        let pos = entryPosition(entry: entry, totalWidth: width)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: max(2, pos.width), height: 14)
                            .offset(x: pos.offset)
                    }
                }
                .frame(height: 32)
            }
            .frame(height: 32)
        }
    }

    // MARK: - Timeline Helpers

    private let ticketColors: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .cyan, .yellow, .mint, .indigo, .teal,
    ]

    private struct EntryPosition {
        let offset: CGFloat
        let width: CGFloat
    }

    private func entryPosition(
        entry: TimeEntry, totalWidth: CGFloat
    ) -> EntryPosition {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let totalSeconds: Double = 24 * 3600

        let segStart = entry.startTime.timeIntervalSince(startOfDay)
        let segEnd = (entry.endTime ?? Date()).timeIntervalSince(startOfDay)

        let clampedStart = max(0, min(segStart, totalSeconds))
        let clampedEnd = max(0, min(segEnd, totalSeconds))

        let xStart = totalWidth * CGFloat(clampedStart / totalSeconds)
        let xEnd = totalWidth * CGFloat(clampedEnd / totalSeconds)

        return EntryPosition(offset: xStart, width: xEnd - xStart)
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
