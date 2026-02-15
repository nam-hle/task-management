import SwiftUI
import SwiftData
import AppKit

// MARK: - Environment Key

private struct JiraServiceKey: EnvironmentKey {
    static let defaultValue: JiraService? = nil
}

extension EnvironmentValues {
    var jiraService: JiraService? {
        get { self[JiraServiceKey.self] }
        set { self[JiraServiceKey.self] = newValue }
    }
}

// MARK: - Ticket Hover Popover

private let ticketIDPattern = #/^[A-Z][A-Z0-9]+-\d+$/#

struct JiraHoverModifier: ViewModifier {
    let ticketID: String

    @Environment(\.jiraService) private var jiraService
    @State private var isHovering = false
    @State private var ticketInfo: JiraTicketInfo?
    @State private var hasFetched = false

    private var isValidTicket: Bool {
        ticketID != "unassigned"
            && ticketID.wholeMatch(of: ticketIDPattern) != nil
    }

    func body(content: Content) -> some View {
        if isValidTicket {
            content
                .onHover { hovering in
                    isHovering = hovering
                    if hovering && !hasFetched {
                        hasFetched = true
                        Task {
                            ticketInfo = await jiraService?
                                .ticketInfo(for: ticketID)
                        }
                    }
                }
                .popover(isPresented: $isHovering) {
                    ticketPopoverContent
                }
        } else {
            content
        }
    }

    private var ticketPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = ticketInfo {
                HStack(spacing: 6) {
                    if let type = info.issueType {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(info.ticketID)
                        .font(.headline)
                    Spacer()
                    statusBadge(
                        info.status,
                        categoryKey: info.statusCategoryKey
                    )
                }

                Text(info.summary)
                    .font(.callout)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    if let assignee = info.assignee {
                        Label(assignee, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let priority = info.priority {
                        Label(priority, systemImage: "flag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = info.browseURL {
                    Divider()
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(
                            "Open in Jira",
                            systemImage: "arrow.up.right.square"
                        )
                        .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading \(ticketID)...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }

    private func statusBadge(
        _ status: String, categoryKey: String
    ) -> some View {
        let color: Color = switch categoryKey {
        case "done": .green
        case "indeterminate": .blue
        case "new": .secondary
        default: .secondary
        }
        return Text(status)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Source Duration Hover

struct SourceDurationHoverModifier: ViewModifier {
    let sources: [TicketsView.DetectedSource]

    @State private var isHovering = false

    func body(content: Content) -> some View {
        if sources.count > 1 {
            content
                .onHover { isHovering = $0 }
                .popover(isPresented: $isHovering) {
                    sourcePopoverContent
                }
        } else {
            content
        }
    }

    private var sourcePopoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration by source")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(sources) { source in
                HStack(spacing: 6) {
                    TicketsView.sourceIconStatic(source.label)
                    Text(source.label)
                        .font(.callout)
                    Spacer()
                    Text(formatDuration(source.duration))
                        .font(.system(
                            .callout, design: .monospaced
                        ))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 200)
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

// MARK: - View Extensions

extension View {
    func jiraHoverPopover(ticketID: String) -> some View {
        modifier(JiraHoverModifier(ticketID: ticketID))
    }

    func sourceDurationHover(
        sources: [TicketsView.DetectedSource]
    ) -> some View {
        modifier(SourceDurationHoverModifier(sources: sources))
    }
}
