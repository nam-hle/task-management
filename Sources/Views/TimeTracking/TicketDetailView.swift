import SwiftUI
import SwiftData

struct TicketDetailView: View {
    let ticket: TicketAggregate

    @State private var isExpanded = false
    @State private var refreshTick = 0

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pluginDetections) { detection in
                    detectionRow(detection)
                }
            }
            .padding(.top, 8)
        } label: {
            ticketHeader
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
    }

    // MARK: - Header

    private var hasInProgressEntries: Bool {
        ticket.entries.contains { $0.isInProgress }
    }

    private var liveDuration: TimeInterval {
        _ = refreshTick
        return TicketAggregationService.deduplicatedDuration(entries: ticket.entries)
    }

    private var ticketHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "ticket")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(ticket.ticketID)
                .font(.headline)
                .jiraHoverPopover(ticketID: ticket.ticketID)

            Text("\(ticket.sourceBreakdown.count) source\(ticket.sourceBreakdown.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text(formatDuration(liveDuration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            if hasInProgressEntries {
                refreshTick &+= 1
            }
        }
    }

    // MARK: - Plugin Detections

    private struct PluginDetection: Identifiable {
        let id: String
        let pluginID: String
        let pluginName: String
        let detectedFrom: String?
        let ticketID: String
        let url: String?
        let pageTitle: String?
        let appName: String?
        let project: String?
        let branch: String?
        let duration: TimeInterval
        let entryCount: Int

        var displayLabel: String {
            if pluginID == "wakatime" { return "Code" }
            switch detectedFrom {
            case "jira": return "Jira"
            case "bitbucket": return "Bitbucket"
            default: return pluginName
            }
        }
    }

    private var pluginDetections: [PluginDetection] {
        // Group by detection source (jira/bitbucket/wakatime) not browser
        var bySource: [String: [TimeEntry]] = [:]
        for entry in ticket.entries {
            let key = detectionKey(for: entry)
            bySource[key, default: []].append(entry)
        }

        return bySource.map { sourceKey, entries in
            let firstWithMeta = entries.first { $0.contextMetadata != nil }
            let meta = parseMetadata(firstWithMeta?.contextMetadata)
            let pluginID = entries.first?.sourcePluginID ?? "unknown"

            return PluginDetection(
                id: sourceKey,
                pluginID: pluginID,
                pluginName: pluginDisplayName(pluginID),
                detectedFrom: sourceKey,
                ticketID: ticket.ticketID,
                url: meta["pageURL"],
                pageTitle: meta["pageTitle"],
                appName: entries.first?.applicationName,
                project: meta["project"],
                branch: meta["branch"],
                duration: entries.reduce(0) { $0 + $1.effectiveDuration },
                entryCount: entries.count
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    private func detectionKey(for entry: TimeEntry) -> String {
        if entry.sourcePluginID == "wakatime" { return "wakatime" }
        let meta = parseMetadata(entry.contextMetadata)
        if let detected = meta["detectedFrom"],
           detected == "jira" || detected == "bitbucket" {
            return detected
        }
        // Fallback: infer from URL
        if let url = meta["pageURL"] {
            if url.contains("/browse/") { return "jira" }
            if url.contains("/pull-requests/") { return "bitbucket" }
        }
        // Fallback: infer from page title (Firefox has no URL)
        if let title = meta["pageTitle"]?.lowercased() {
            if title.contains("pull request") || title.contains("bitbucket") {
                return "bitbucket"
            }
            if title.contains("jira") { return "jira" }
        }
        return entry.sourcePluginID ?? "unknown"
    }

    private func detectionRow(_ detection: PluginDetection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            detectionIcon(for: detection)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(detection.displayLabel)
                        .font(.callout.bold())
                    Text(detection.displayLabel)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    Spacer()
                    Text(formatDuration(detection.duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if detection.pluginID == "wakatime" {
                    let project = detection.project
                        ?? detection.appName ?? "Unknown"
                    let branch = detection.branch ?? ""
                    if branch.isEmpty {
                        Text(project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(project) > \(branch)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let url = detection.url {
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .bitbucketHoverPopover(prURL: url)
                    }

                    if let title = detection.pageTitle,
                       detection.url != nil {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detectionIcon(for detection: PluginDetection) -> some View {
        switch detection.displayLabel {
        case "Code":
            Image(systemName: "chevronleft.forwardslash.chevronright")
                .foregroundStyle(.green)
                .font(.caption)
        case "Jira":
            Image(systemName: "list.clipboard")
                .foregroundStyle(.blue)
                .font(.caption)
        case "Bitbucket":
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.blue)
                .font(.caption)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func pluginDisplayName(_ pluginID: String) -> String {
        switch pluginID {
        case "wakatime": "WakaTime"
        case "chrome": "Chrome"
        case "firefox": "Firefox"
        default: pluginID
        }
    }

    private func parseMetadata(_ json: String?) -> [String: String] {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [String: String] = [:]
        for (key, value) in dict {
            if let str = value as? String {
                result[key] = str
            }
        }
        return result
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
