import SwiftUI

struct BranchesView: View {
    let wakaTimeService: WakaTimeService

    private var totalDuration: TimeInterval {
        wakaTimeService.branches.reduce(0.0) { $0 + $1.totalDuration }
    }

    /// Group branches by project name for the list section.
    private var projectGroups: [(project: String, branches: [BranchActivity])] {
        var grouped: [String: [BranchActivity]] = [:]
        for branch in wakaTimeService.branches {
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
            header
            Divider()
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                Text(formatDuration(totalDuration))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                Task {
                    await wakaTimeService.fetchBranches(for: Date())
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh WakaTime data")
            .disabled(wakaTimeService.isLoading)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !wakaTimeService.isConfigured {
            notConfiguredState
        } else if wakaTimeService.isLoading && wakaTimeService.branches.isEmpty {
            loadingState
        } else if let error = wakaTimeService.error {
            errorState(error)
        } else if wakaTimeService.branches.isEmpty {
            emptyState
        } else {
            dataView
        }
    }

    // MARK: - States

    private var notConfiguredState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("WakaTime not configured")
                .foregroundStyle(.secondary)
            Text("Add your API key to ~/.wakatime.cfg")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading WakaTime data...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ error: WakaTimeError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to load data")
                .foregroundStyle(.secondary)
            Text(error.errorDescription ?? "Unknown error")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("Retry") {
                Task {
                    await wakaTimeService.fetchBranches(for: Date())
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No branch activity today")
                .foregroundStyle(.secondary)
            Text("WakaTime data will appear here as you code")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data View

    private var dataView: some View {
        ScrollView {
            VStack(spacing: 16) {
                BranchTimelineChartView(
                    branches: wakaTimeService.branches, date: Date()
                )
                .padding(.top, 8)

                Divider()

                // Grouped by project
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(projectGroups, id: \.project) { group in
                        projectSection(group.project, branches: group.branches)
                    }
                }
            }
            .padding()
        }
    }

    private func projectSection(
        _ project: String, branches: [BranchActivity]
    ) -> some View {
        let projectTotal = branches.reduce(0.0) { $0 + $1.totalDuration }

        return VStack(alignment: .leading, spacing: 4) {
            // Project header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(project)
                    .font(.headline)
                Spacer()
                Text(formatDuration(projectTotal))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Branch rows
            ForEach(branches) { branch in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                    Text(branch.branch)
                        .font(.callout)
                    Spacer()
                    Text(formatDuration(branch.totalDuration))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
