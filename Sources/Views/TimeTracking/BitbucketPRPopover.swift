import SwiftUI

// MARK: - Environment Key

private struct BitbucketServiceKey: EnvironmentKey {
    static let defaultValue: BitbucketService? = nil
}

extension EnvironmentValues {
    var bitbucketService: BitbucketService? {
        get { self[BitbucketServiceKey.self] }
        set { self[BitbucketServiceKey.self] = newValue }
    }
}

// MARK: - Popover View

struct BitbucketPRPopover: View {
    let info: BitbucketPRInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(.secondary)
                Text("PR #\(info.prNumber)")
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

            Text(info.title)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            fieldRow("Status", icon: "circle.fill") { statusBadge }

            fieldRow("Author", icon: "person") {
                Text(info.author).font(.caption)
            }

            fieldRow("Branch", icon: "arrow.triangle.branch") {
                Text(info.sourceBranch)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }

            if !info.reviewers.isEmpty {
                fieldRow("Reviewers", icon: "person.2") {
                    Text(info.reviewers.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(2)
                }
            }

            if let ticketID = info.ticketID {
                fieldRow("Ticket", icon: "ticket") {
                    Text(ticketID).font(.caption)
                }
            }
        }
        .padding(10)
        .frame(width: 300, alignment: .leading)
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
                .frame(width: 60, alignment: .leading)
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
        switch info.status.uppercased() {
        case "OPEN": .blue
        case "MERGED": .purple
        case "DECLINED": .red
        default: .secondary
        }
    }
}

// MARK: - Hover Modifier

struct BitbucketHoverModifier: ViewModifier {
    let prURL: String

    @Environment(\.bitbucketService) private var bitbucketService
    @Environment(\.logService) private var logService
    @State private var prInfo: BitbucketPRInfo?
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var popoverHovering = false

    private var isValidURL: Bool {
        prURL.contains("/pull-requests/")
    }

    func body(content: Content) -> some View {
        if let service = bitbucketService, isValidURL {
            content
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        dismissTask?.cancel()
                        dismissTask = nil
                        logService?.log(
                            "Hover on BB PR: \(prURL), prefetching"
                        )
                        service.prefetch(prURL: prURL)
                        hoverTask?.cancel()
                        hoverTask = Task {
                            try? await Task.sleep(
                                for: .milliseconds(400)
                            )
                            guard !Task.isCancelled,
                                  isHovering else { return }
                            let info = await service.prInfo(for: prURL)
                            if info != nil {
                                logService?.log(
                                    "Showing popover for BB PR: \(prURL)"
                                )
                            }
                            prInfo = info
                        }
                    } else {
                        hoverTask?.cancel()
                        hoverTask = nil
                        scheduleDismiss()
                    }
                }
                .popover(
                    item: $prInfo, arrowEdge: .bottom
                ) { info in
                    BitbucketPRPopover(info: info)
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
                prInfo = nil
            }
        }
    }
}

extension View {
    func bitbucketHoverPopover(prURL: String) -> some View {
        modifier(BitbucketHoverModifier(prURL: prURL))
    }
}
