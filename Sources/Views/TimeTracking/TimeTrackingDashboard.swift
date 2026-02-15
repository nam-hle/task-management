import SwiftUI
import SwiftData

struct TimeTrackingDashboard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TrackingCoordinator.self) private var coordinator
    @Query(sort: \TimeEntry.startTime, order: .forward)
    private var allEntries: [TimeEntry]

    @State private var wakaTimeService = WakaTimeService()
    @State private var selectedTab = "tickets"

    private var todayEntries: [TimeEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allEntries.filter { $0.startTime >= startOfDay }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TicketsView(wakaTimeService: wakaTimeService)
                .tabItem {
                    Label("Tickets", systemImage: "ticket")
                }
                .tag("tickets")

            BranchesView(wakaTimeService: wakaTimeService)
                .tabItem {
                    Label("Branches", systemImage: "arrow.triangle.branch")
                }
                .tag("branches")

            applicationsContent
                .tabItem {
                    Label("Applications", systemImage: "app.dashed")
                }
                .tag("applications")

            TimeEntryListView()
                .tabItem {
                    Label("Entries", systemImage: "list.bullet.rectangle")
                }
                .tag("entries")

            ExportView()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag("export")
        }
        .navigationTitle("Time Tracking")
        .task {
            await wakaTimeService.fetchBranches(for: Date())
        }
    }

    private var applicationsContent: some View {
        VStack(spacing: 0) {
            dashboardHeader

            Divider()

            if todayEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        TimelineChartView(entries: todayEntries, date: Date())
                            .padding(.top, 8)

                        Divider()

                        LazyVStack(spacing: 1) {
                            ForEach(todayEntries) { entry in
                                TimeEntryRow(entry: entry)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                Text(dailyTotal)
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            trackingStatus
        }
        .padding()
    }

    private var trackingStatus: some View {
        HStack(spacing: 12) {
            if case .tracking = coordinator.state {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text(coordinator.currentAppName ?? "Tracking")
                        .font(.headline)
                }
                Text(formatElapsed(coordinator.elapsedSeconds))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button {
                    coordinator.pause(reason: .userPaused)
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Pause tracking")
            } else if case .paused = coordinator.state {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Paused")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
                Button("Resume") {
                    coordinator.resume()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if case .permissionRequired = coordinator.state {
                Text("Accessibility permission needed")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No time entries today")
                .foregroundStyle(.secondary)
            Text("Start tracking to see your daily activity")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var dailyTotal: String {
        let total = todayEntries.reduce(0.0) { $0 + $1.effectiveDuration }
        return formatDuration(total)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
