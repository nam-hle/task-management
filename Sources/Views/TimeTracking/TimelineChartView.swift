import SwiftUI

struct TimelineChartView: View {
    let entries: [TimeEntry]
    let date: Date

    private let labelWidth: CGFloat = 200
    private let rowHeight: CGFloat = 32
    private let barHeight: CGFloat = 14
    private let headerHeight: CGFloat = 30

    private let appColors: [Color] = [
        .green, .pink, .blue, .cyan, .orange, .purple, .yellow, .mint, .indigo, .teal
    ]

    private var appRows: [AppRow] {
        var grouped: [String: [TimeEntry]] = [:]
        for entry in entries {
            let name = entry.applicationName ?? entry.label ?? "Unknown"
            grouped[name, default: []].append(entry)
        }
        return grouped.map { name, entries in
            let total = entries.reduce(0.0) { $0 + $1.effectiveDuration }
            return AppRow(appName: name, entries: entries, totalDuration: total)
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    private var startOfDay: Date {
        Calendar.current.startOfDay(for: date)
    }

    private let totalSeconds: Double = 24 * 3600

    var body: some View {
        VStack(spacing: 0) {
            // Hour markers header
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: labelWidth)
                hourMarkersHeader
            }

            // App rows
            ForEach(Array(appRows.enumerated()), id: \.element.appName) { index, row in
                HStack(spacing: 0) {
                    // Label: app name + duration
                    HStack(spacing: 8) {
                        Spacer()
                        Text(row.appName)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(formatDuration(row.totalDuration))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: labelWidth)
                    .padding(.trailing, 8)

                    // Timeline bar
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.quaternary.opacity(0.3))
                                .frame(height: barHeight)

                            // Entry segments
                            let color = appColors[index % appColors.count]
                            ForEach(row.entries, id: \.id) { entry in
                                let segment = segmentPosition(
                                    entry: entry, totalWidth: width
                                )
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color)
                                    .frame(
                                        width: max(2, segment.width),
                                        height: barHeight
                                    )
                                    .offset(x: segment.offset)
                            }
                        }
                        .frame(height: rowHeight)
                    }
                    .frame(height: rowHeight)
                }

                if index < appRows.count - 1 {
                    Divider()
                        .padding(.leading, labelWidth)
                        .opacity(0.3)
                }
            }
        }
    }

    // MARK: - Hour Markers

    private var hourMarkersHeader: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                // Hour labels
                ForEach(hourLabels, id: \.hour) { label in
                    let x = width * CGFloat(label.hour) / 24.0
                    Text(label.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .position(x: x, y: headerHeight / 2)
                }

                // Tick marks
                ForEach(0..<25, id: \.self) { hour in
                    let x = width * CGFloat(hour) / 24.0
                    Rectangle()
                        .fill(.tertiary.opacity(0.3))
                        .frame(width: 1, height: 6)
                        .position(x: x, y: headerHeight - 3)
                }
            }
        }
        .frame(height: headerHeight)
    }

    private struct HourLabel {
        let hour: Int
        let text: String
    }

    private var hourLabels: [HourLabel] {
        stride(from: 0, through: 23, by: 3).map { hour in
            let text: String
            if hour == 0 {
                text = "12a"
            } else if hour < 12 {
                text = "\(hour)a"
            } else if hour == 12 {
                text = "12p"
            } else {
                text = "\(hour - 12)p"
            }
            return HourLabel(hour: hour, text: text)
        }
    }

    // MARK: - Segment Positioning

    private struct SegmentPosition {
        let offset: CGFloat
        let width: CGFloat
    }

    private func segmentPosition(entry: TimeEntry, totalWidth: CGFloat) -> SegmentPosition {
        let entryStart = entry.startTime.timeIntervalSince(startOfDay)
        let entryEnd: TimeInterval
        if let end = entry.endTime {
            entryEnd = end.timeIntervalSince(startOfDay)
        } else {
            entryEnd = Date().timeIntervalSince(startOfDay)
        }

        let clampedStart = max(0, min(entryStart, totalSeconds))
        let clampedEnd = max(0, min(entryEnd, totalSeconds))

        let xStart = totalWidth * CGFloat(clampedStart / totalSeconds)
        let xEnd = totalWidth * CGFloat(clampedEnd / totalSeconds)

        return SegmentPosition(offset: xStart, width: xEnd - xStart)
    }

    // MARK: - Helpers

    private struct AppRow {
        let appName: String
        let entries: [TimeEntry]
        let totalDuration: TimeInterval
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        }
        return "0:\(String(format: "%02d", minutes))"
    }
}
