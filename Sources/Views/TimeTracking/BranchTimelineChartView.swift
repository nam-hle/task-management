import SwiftUI

struct BranchTimelineChartView: View {
    let branches: [BranchActivity]
    let date: Date

    private let labelWidth: CGFloat = 300
    private let rowHeight: CGFloat = 32
    private let barHeight: CGFloat = 14
    private let headerHeight: CGFloat = 30

    private let projectHeaderHeight: CGFloat = 28
    private let branchColors: [Color] = [
        .green, .pink, .blue, .cyan, .orange, .purple, .yellow, .mint, .indigo, .teal
    ]

    private var startOfDay: Date {
        Calendar.current.startOfDay(for: date)
    }

    private let totalSeconds: Double = 24 * 3600

    private var projectGroups: [(project: String, branches: [BranchActivity])] {
        var grouped: [String: [BranchActivity]] = [:]
        for branch in branches {
            grouped[branch.project, default: []].append(branch)
        }
        return grouped
            .map { (project: $0.key, branches: $0.value) }
            .sorted { lhs, rhs in
                let lhsTotal = lhs.branches.reduce(0.0) { $0 + $1.totalDuration }
                let rhsTotal = rhs.branches.reduce(0.0) { $0 + $1.totalDuration }
                return lhsTotal > rhsTotal
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hour markers header
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: labelWidth)
                hourMarkersHeader
            }

            // Project groups
            var colorIndex = 0
            ForEach(Array(projectGroups.enumerated()), id: \.element.project) {
                groupIdx, group in
                let projectTotal = group.branches.reduce(0.0) { $0 + $1.totalDuration }

                // Project header row
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(group.project)
                            .font(.callout.bold())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(formatDuration(projectTotal))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(width: labelWidth)
                    .frame(height: projectHeaderHeight)
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    Spacer()
                }
                .background(.quaternary.opacity(0.15))

                // Branch rows within project
                ForEach(
                    Array(group.branches.enumerated()), id: \.element.id
                ) { branchIdx, branch in
                    let currentColor = branchColors[
                        (colorIndex + branchIdx) % branchColors.count
                    ]
                    branchRow(branch: branch, color: currentColor)

                    if branchIdx < group.branches.count - 1 {
                        Divider()
                            .padding(.leading, labelWidth)
                            .opacity(0.3)
                    }
                }

                let _ = { colorIndex += group.branches.count }()

                if groupIdx < projectGroups.count - 1 {
                    Divider().opacity(0.5)
                }
            }
        }
    }

    private func branchRow(branch: BranchActivity, color: Color) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text(branch.branch)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatDuration(branch.totalDuration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: labelWidth)
            .padding(.leading, 24)
            .padding(.trailing, 8)

            // Timeline bar
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary.opacity(0.3))
                        .frame(height: barHeight)

                    ForEach(branch.segments) { segment in
                        let pos = segmentPosition(
                            segment: segment, totalWidth: width
                        )
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(
                                width: max(2, pos.width),
                                height: barHeight
                            )
                            .offset(x: pos.offset)
                    }
                }
                .frame(height: rowHeight)
            }
            .frame(height: rowHeight)
        }
    }

    // MARK: - Hour Markers

    private var hourMarkersHeader: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(hourLabels, id: \.hour) { label in
                    let x = width * CGFloat(label.hour) / 24.0
                    Text(label.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .position(x: x, y: headerHeight / 2)
                }

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

    private func segmentPosition(
        segment: BranchSegment, totalWidth: CGFloat
    ) -> SegmentPosition {
        let segStart = segment.start.timeIntervalSince(startOfDay)
        let segEnd = segment.end.timeIntervalSince(startOfDay)

        let clampedStart = max(0, min(segStart, totalSeconds))
        let clampedEnd = max(0, min(segEnd, totalSeconds))

        let xStart = totalWidth * CGFloat(clampedStart / totalSeconds)
        let xEnd = totalWidth * CGFloat(clampedEnd / totalSeconds)

        return SegmentPosition(offset: xStart, width: xEnd - xStart)
    }

    // MARK: - Helpers

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
