import SwiftUI
import SwiftData

struct TicketsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntry.startTime, order: .reverse)
    private var allEntries: [TimeEntry]

    @Environment(TrackingCoordinator.self) private var coordinator

    @State private var selectedDate = Date()
    @State private var refreshTick = 0
    @State private var isSyncing = false

    private var entriesForDate: [TimeEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(
            byAdding: .day, value: 1, to: startOfDay
        )!
        return allEntries.filter {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
                && !$0.isExcluded
                && $0.source != .manual && $0.source != .timer
        }
    }

    private var tickets: [TicketAggregate] {
        _ = refreshTick
        return TicketAggregationService.aggregate(
            entries: entriesForDate
        )
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
        return TicketAggregationService.deduplicatedDuration(
            entries: entriesForDate
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
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
                Task {
                    isSyncing = true
                    await coordinator.syncPlugins()
                    isSyncing = false
                }
            } label: {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isSyncing)
            .help("Refresh plugin data")

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
            Text(
                "Time entries will appear here"
                + " as plugins track your activity"
            )
            .font(.callout)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data View

    private var dataView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ticketTimeline
                    .padding(.top, 8)

                if let unassigned = unassignedTicket {
                    Divider()
                        .padding(.vertical, 12)
                    UnassignedTimeView(entries: unassigned.entries)
                }
            }
            .padding()
        }
    }

    // MARK: - Timeline

    private var ticketTimeline: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(
                    assignedTickets.prefix(10).enumerated()
                ),
                id: \.element.id
            ) { index, ticket in
                let color = ticketColors[index % ticketColors.count]
                ticketTimelineRow(
                    ticket: ticket, color: color
                )

                if index < min(assignedTickets.count, 10) - 1 {
                    Divider().opacity(0.5)
                }
            }

            if let unassigned = unassignedTicket {
                Divider().opacity(0.5)
                unassignedTimelineRow(ticket: unassigned)
            }

            timelineAxisLabels
            sourceLegend
        }
    }

    private func ticketTimelineRow(
        ticket: TicketAggregate, color: Color
    ) -> some View {
        let sources = detectSources(for: ticket)
        return TicketTimelineRowView(
            ticket: ticket,
            sources: sources,
            color: color,
            selectedDate: selectedDate
        )
    }

    private func unassignedTimelineRow(
        ticket: TicketAggregate
    ) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Unassigned")
                    .font(.callout.bold())
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Text(formatDuration(ticket.totalDuration))
                    .font(.system(
                        .callout, design: .monospaced
                    ))
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
                        let pos = entryPosition(
                            entry: entry,
                            totalWidth: width
                        )
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.gray)
                            .frame(
                                width: max(2, pos.width),
                                height: 14
                            )
                            .offset(x: pos.offset)
                    }
                }
                .frame(height: 32)
            }
            .frame(height: 32)
        }
    }

    struct DetectedSource: Identifiable {
        let id: String
        let label: String
        let duration: TimeInterval
    }

    private func detectSources(
        for ticket: TicketAggregate
    ) -> [DetectedSource] {
        var bySource: [String: TimeInterval] = [:]
        for entry in ticket.entries {
            let key = detectionLabel(for: entry)
            bySource[key, default: 0] += entry.effectiveDuration
        }
        return bySource.map { label, duration in
            DetectedSource(
                id: label, label: label, duration: duration
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    private func detectionLabel(for entry: TimeEntry) -> String {
        if entry.sourcePluginID == "wakatime" { return "Code" }
        if let meta = entry.contextMetadata,
           let data = meta.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data)
               as? [String: Any]
        {
            if let detected = dict["detectedFrom"] as? String {
                switch detected {
                case "jira": return "Jira"
                case "bitbucket": return "Bitbucket"
                default: break
                }
            }
            if let url = dict["pageURL"] as? String {
                if url.contains("/browse/") { return "Jira" }
                if url.contains("/pull-requests/") {
                    return "Bitbucket"
                }
            }
            if let title = (dict["pageTitle"] as? String)?
                .lowercased()
            {
                if title.contains("pull request")
                    || title.contains("bitbucket")
                {
                    return "Bitbucket"
                }
                if title.contains("jira") { return "Jira" }
            }
        }
        switch entry.sourcePluginID {
        case "chrome": return "Chrome"
        case "firefox": return "Firefox"
        default: return entry.source.label
        }
    }

    @ViewBuilder
    func sourceIcon(_ label: String) -> some View {
        Self.sourceIconStatic(label)
    }

    @ViewBuilder
    static func sourceIconStatic(_ label: String) -> some View {
        switch label {
        case "Code":
            Image(
                systemName: "chevronleft.forwardslash.chevronright"
            )
            .font(.system(size: 8))
            .foregroundStyle(.green)
        case "Jira":
            Image(systemName: "list.clipboard")
                .font(.system(size: 8))
                .foregroundStyle(.blue)
        case "Bitbucket":
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8))
                .foregroundStyle(.blue)
        default:
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Legend

    private var sourceLegend: some View {
        HStack(spacing: 12) {
            Spacer()
            legendItem(
                "Code",
                icon: "chevronleft.forwardslash.chevronright",
                color: .green
            )
            legendItem(
                "Jira",
                icon: "list.clipboard",
                color: .blue
            )
            legendItem(
                "Bitbucket",
                icon: "arrow.triangle.branch",
                color: .blue
            )
            legendItem(
                "Browser",
                icon: "globe",
                color: .secondary
            )
        }
        .padding(.top, 4)
    }

    private func legendItem(
        _ label: String, icon: String, color: Color
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Axis Labels

    private var timelineAxisLabels: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 200)
                .padding(.leading, 8)

            GeometryReader { geometry in
                let width = geometry.size.width
                let totalSeconds: Double = 24 * 3600
                let hours = Array(0..<24)

                ForEach(hours, id: \.self) { hour in
                    let x = width
                        * CGFloat(Double(hour) * 3600 / totalSeconds)
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: x, y: 10)
                }
            }
            .frame(height: 20)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
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
        let startOfDay = Calendar.current.startOfDay(
            for: selectedDate
        )
        let totalSeconds: Double = 24 * 3600

        let segStart = entry.startTime.timeIntervalSince(startOfDay)
        let segEnd = (entry.endTime ?? Date())
            .timeIntervalSince(startOfDay)

        let clampedStart = max(0, min(segStart, totalSeconds))
        let clampedEnd = max(0, min(segEnd, totalSeconds))

        let xStart = totalWidth
            * CGFloat(clampedStart / totalSeconds)
        let xEnd = totalWidth
            * CGFloat(clampedEnd / totalSeconds)

        return EntryPosition(
            offset: xStart, width: xEnd - xStart
        )
    }

    // MARK: - Helpers

    private func formatDuration(
        _ interval: TimeInterval
    ) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
