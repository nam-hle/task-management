import SwiftUI

struct TicketTimelineRowView: View {
    let ticket: TicketAggregate
    let sources: [TicketsView.DetectedSource]
    let color: Color
    let selectedDate: Date

    @Environment(\.jiraService) private var jiraService
    @State private var summary: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(ticket.ticketID)
                        .font(.callout.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .jiraHoverPopover(
                            ticketID: ticket.ticketID
                        )
                    Spacer()
                    Text(formatDuration(ticket.totalDuration))
                        .font(.system(
                            .callout, design: .monospaced
                        ))
                        .foregroundStyle(.secondary)
                        .sourceDurationHover(sources: sources)
                }
                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: 200, alignment: .leading)
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
                            .fill(color)
                            .frame(
                                width: max(2, pos.width),
                                height: 14
                            )
                            .offset(x: pos.offset)
                    }
                }
            }
            .frame(height: 32)
        }
        .task {
            guard summary == nil else { return }
            let info = await jiraService?.ticketInfo(
                for: ticket.ticketID
            )
            summary = info?.summary
        }
    }

    // MARK: - Timeline Position

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

    private struct EntryPosition {
        let offset: CGFloat
        let width: CGFloat
    }

    private func formatDuration(
        _ interval: TimeInterval
    ) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
