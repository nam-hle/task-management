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
                    Text(timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let source = sourceLabel {
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
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

            Text(entry.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        entry.applicationName ?? entry.label ?? "Untitled"
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: entry.startTime)
        if let end = entry.endTime {
            return "\(start) – \(formatter.string(from: end))"
        }
        return "\(start) – now"
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
            switch entry.source {
            case .autoDetected:
                Image(systemName: "wand.and.rays")
                    .foregroundStyle(.blue)
            case .manual:
                Image(systemName: "hand.tap")
                    .foregroundStyle(.orange)
            case .timer:
                Image(systemName: "timer")
                    .foregroundStyle(.purple)
            case .wakatime:
                Image(systemName: "keyboard")
                    .foregroundStyle(.green)
            case .edited:
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
    }

    private var sourceLabel: String? {
        switch entry.source {
        case .autoDetected: nil
        case .manual: "Manual"
        case .timer: "Timer"
        case .wakatime: "WakaTime"
        case .edited: "Edited"
        }
    }
}
