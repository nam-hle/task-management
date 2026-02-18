import SwiftUI

struct TimeEntryRow: View {
    let entry: TimeEntry

    var body: some View {
        HStack(spacing: 12) {
            sourceIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(Formatters.timeRange(start: entry.startTime, end: entry.endTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pluginLabel)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                if let url = browserURL {
                    Text(url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            statusBadge

            if entry.isAutoApproved {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .help("Auto-approved by learned pattern")
            }

            if entry.isInProgress {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if entry.isExcluded {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .help("Excluded from tracking")
            }

            Text(entry.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(entry.isExcluded ? 0.5 : 1.0)
    }

    private var displayName: String {
        if entry.sourcePluginID == "wakatime" {
            let meta = parseMetadata(entry.contextMetadata)
            let project = meta["project"] ?? entry.applicationName ?? "Unknown"
            let branch = meta["branch"] ?? ""
            let ticket = entry.ticketID.map { "[\($0)] " } ?? ""
            if branch.isEmpty {
                return "\(ticket)\(project)"
            }
            return "\(ticket)\(project) > \(branch)"
        }
        if isBrowserEntry, let ticketID = entry.ticketID {
            return ticketID
        }
        return entry.applicationName ?? entry.label ?? "Untitled"
    }

    private var isBrowserEntry: Bool {
        entry.source == .chrome || entry.source == .firefox
    }

    private var browserURL: String? {
        guard isBrowserEntry, let meta = entry.contextMetadata,
              let data = meta.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["pageURL"] as? String
    }

    private func parseMetadata(_ json: String?) -> [String: String] {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if let str = value as? String { result[key] = str }
        }
        return result
    }


    @ViewBuilder
    private var statusBadge: some View {
        switch entry.bookingStatus {
        case .reviewed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help("Reviewed")
        case .exported:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .font(.caption)
                .help("Exported")
        case .booked:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.purple)
                .font(.caption)
                .help("Booked")
        case .unreviewed:
            EmptyView()
        }
    }

    private var sourceIcon: some View {
        Group {
            switch pluginLabel {
            case "Code":
                Image(systemName: "chevronleft.forwardslash.chevronright")
                    .foregroundStyle(.green)
            case "Jira":
                Image(systemName: "list.clipboard")
                    .foregroundStyle(.blue)
            case "Bitbucket":
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.blue)
            case "Manual":
                Image(systemName: "hand.tap")
                    .foregroundStyle(.orange)
            case "Timer":
                Image(systemName: "timer")
                    .foregroundStyle(.purple)
            case "Edited":
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.yellow)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var pluginLabel: String {
        if entry.sourcePluginID == "wakatime" { return "Code" }
        if entry.sourcePluginID == "chrome" || entry.sourcePluginID == "firefox" {
            let meta = parseMetadata(entry.contextMetadata)
            if let detected = meta["detectedFrom"], !detected.isEmpty {
                switch detected {
                case "jira": return "Jira"
                case "bitbucket": return "Bitbucket"
                default: break
                }
            }
            if let url = meta["pageURL"] {
                if url.contains("/browse/") { return "Jira" }
                if url.contains("/pull-requests/") { return "Bitbucket" }
            }
            if let title = meta["pageTitle"]?.lowercased() {
                if title.contains("pull request") || title.contains("bitbucket") {
                    return "Bitbucket"
                }
                if title.contains("jira") { return "Jira" }
            }
        }
        switch entry.sourcePluginID {
        case "chrome": return "Chrome"
        case "firefox": return "Firefox"
        default:
            switch entry.source {
            case .manual: return "Manual"
            case .timer: return "Timer"
            case .edited: return "Edited"
            default: return "Unknown"
            }
        }
    }
}
