import SwiftUI
import SwiftData
import AppKit

// MARK: - Ticket Hover Popover

private let ticketIDPattern = #/^[A-Z][A-Z0-9]+-\d+$/#

struct JiraHoverModifier: ViewModifier {
    let ticketID: String

    @Environment(\.serviceContainer) private var serviceContainer
    @State private var isHovering = false
    @State private var ticketInfo: JiraTicketInfo?
    @State private var hoverTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var popoverHovering = false

    private var isValidTicket: Bool {
        ticketID != "unassigned"
            && ticketID.wholeMatch(of: ticketIDPattern) != nil
    }

    func body(content: Content) -> some View {
        if let service = serviceContainer?.jiraService, isValidTicket {
            content
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        dismissTask?.cancel()
                        dismissTask = nil
                        service.prefetch(ticketID: ticketID)
                        hoverTask?.cancel()
                        hoverTask = Task {
                            try? await Task.sleep(
                                for: .milliseconds(400)
                            )
                            guard !Task.isCancelled,
                                  isHovering else { return }
                            ticketInfo = await service
                                .ticketInfo(for: ticketID)
                        }
                    } else {
                        hoverTask?.cancel()
                        hoverTask = nil
                        scheduleDismiss()
                    }
                }
                .popover(
                    item: $ticketInfo, arrowEdge: .bottom
                ) { info in
                    ticketPopoverContent(info: info)
                        .onHover { hovering in
                            popoverHovering = hovering
                            if hovering {
                                dismissTask?.cancel()
                                dismissTask = nil
                            } else {
                                scheduleDismiss()
                            }
                        }
                }
        } else {
            content
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if !isHovering && !popoverHovering {
                ticketInfo = nil
            }
        }
    }

    private func ticketPopoverContent(
        info: JiraTicketInfo
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    Text(source.duration.hoursMinutes)
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
