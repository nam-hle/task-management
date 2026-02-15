import SwiftUI

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

// MARK: - Popover View

struct JiraTicketPopover: View {
    let info: JiraTicketInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let issueType = info.issueType {
                    Image(systemName: issueTypeIcon(issueType))
                        .foregroundStyle(.secondary)
                }
                Text(info.ticketID)
                    .font(.headline)

                Spacer()

                if let url = info.browseURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open in browser")
                }
            }

            Text(info.summary)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            fieldRow("Status", icon: "circle.fill") { statusBadge }

            if let issueType = info.issueType {
                fieldRow("Type", icon: "tag") {
                    Text(issueType).font(.caption)
                }
            }

            if let assignee = info.assignee {
                fieldRow("Assignee", icon: "person") {
                    Text(assignee).font(.caption)
                }
            }

            if let priority = info.priority {
                fieldRow("Priority", icon: "flag") {
                    Text(priority).font(.caption)
                }
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
    }

    private func fieldRow<Content: View>(
        _ label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .leading)
            content()
        }
    }

    private var statusBadge: some View {
        Text(info.status)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch info.statusCategoryKey {
        case "new": .blue
        case "indeterminate": .orange
        case "done": .green
        default: .secondary
        }
    }

    private func issueTypeIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "bug": "ladybug"
        case "story", "user story": "book"
        case "task": "checkmark.square"
        case "sub-task", "subtask": "checkmark.square"
        case "epic": "bolt"
        case "improvement": "arrow.up.circle"
        default: "circle"
        }
    }
}

// MARK: - Hover Modifier

private let ticketIDPattern = #/^[A-Z][A-Z0-9]+-\d+$/#

struct JiraHoverModifier: ViewModifier {
    let ticketID: String

    @Environment(\.jiraService) private var jiraService
    @Environment(\.logService) private var logService
    @State private var ticketInfo: JiraTicketInfo?
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var popoverHovering = false

    private var isValidTicket: Bool {
        ticketID != "unassigned" && ticketID.wholeMatch(of: ticketIDPattern) != nil
    }

    func body(content: Content) -> some View {
        if let service = jiraService, isValidTicket {
            content
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        dismissTask?.cancel()
                        dismissTask = nil
                        logService?.log("Hover on \(ticketID), prefetching")
                        service.prefetch(ticketID: ticketID)
                        hoverTask?.cancel()
                        hoverTask = Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled, isHovering else { return }
                            let info = await service.ticketInfo(for: ticketID)
                            if info != nil {
                                logService?.log("Showing popover for \(ticketID)")
                            }
                            ticketInfo = info
                        }
                    } else {
                        hoverTask?.cancel()
                        hoverTask = nil
                        scheduleDismiss()
                    }
                }
                .popover(item: $ticketInfo, arrowEdge: .bottom) { info in
                    JiraTicketPopover(info: info)
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
}

extension View {
    func jiraHoverPopover(ticketID: String) -> some View {
        modifier(JiraHoverModifier(ticketID: ticketID))
    }
}
