import SwiftUI
import SwiftData

struct TicketsView: View {
    let wakaTimeService: WakaTimeService

    @Environment(\.modelContext) private var modelContext
    @Query private var overrides: [TicketOverride]

    @AppStorage("ticketExcludedProjects") private var excludedProjectsData = Data()
    @AppStorage("ticketUnknownPatterns") private var unknownPatternsData = Data()

    @State private var showSettings = false

    private var excludedProjects: Set<String> {
        (try? JSONDecoder().decode([String].self, from: excludedProjectsData))
            .map(Set.init) ?? []
    }

    private var unknownPatterns: [String] {
        (try? JSONDecoder().decode([String].self, from: unknownPatternsData))
            ?? []
    }

    private var tickets: [TicketActivity] {
        TicketInferenceService.inferTickets(
            from: wakaTimeService.branches,
            overrides: overrides,
            excludedProjects: excludedProjects,
            unknownPatterns: unknownPatterns
        )
    }

    private var totalDuration: TimeInterval {
        tickets.reduce(0.0) { $0 + $1.totalDuration }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showSettings) {
            TicketSettingsView(
                wakaTimeService: wakaTimeService,
                excludedProjectsData: $excludedProjectsData,
                unknownPatternsData: $unknownPatternsData
            )
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

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Ticket settings")
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !wakaTimeService.isConfigured {
            notConfiguredState
        } else if wakaTimeService.isLoading
            && wakaTimeService.branches.isEmpty
        {
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
            Image(systemName: "ticket")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No ticket activity today")
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
                TicketTimelineChartView(tickets: tickets, date: Date())
                    .padding(.top, 8)

                Divider()

                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(tickets) { ticket in
                        ticketSection(ticket)
                    }
                }
            }
            .padding()
        }
    }

    private func ticketSection(_ ticket: TicketActivity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Ticket header
            HStack(spacing: 6) {
                Image(systemName: ticket.ticketID != nil
                    ? "ticket" : "questionmark.circle")
                    .foregroundStyle(ticket.ticketID != nil
                        ? Color.secondary : Color.orange)
                    .font(.caption)
                Text(ticket.ticketID ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(
                        ticket.ticketID != nil ? .primary : .secondary
                    )
                Spacer()
                Text(formatDuration(ticket.totalDuration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Branch rows
            ForEach(ticket.branches) { branch in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                    Text(branch.branch)
                        .font(.callout)
                    Text(branch.project)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(formatDuration(branch.totalDuration))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if ticket.ticketID == nil {
                        AssignTicketButton(
                            project: branch.project,
                            branch: branch.branch,
                            modelContext: modelContext
                        )
                    }
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

// MARK: - Assign Ticket Button

private struct AssignTicketButton: View {
    let project: String
    let branch: String
    let modelContext: ModelContext

    @State private var showPopover = false
    @State private var ticketInput = ""

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Text("Assign")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .popover(isPresented: $showPopover) {
            VStack(spacing: 8) {
                Text("Assign ticket to \(branch)")
                    .font(.headline)
                    .lineLimit(1)

                TextField("Ticket ID (e.g. PROJ-123)", text: $ticketInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        saveOverride()
                    }

                HStack {
                    Button("Cancel") {
                        showPopover = false
                        ticketInput = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        saveOverride()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ticketInput.trimmingCharacters(
                        in: .whitespaces
                    ).isEmpty)
                }
            }
            .padding()
        }
    }

    private func saveOverride() {
        let trimmed = ticketInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let override = TicketOverride(
            project: project,
            branch: branch,
            ticketID: trimmed
        )
        modelContext.insert(override)
        try? modelContext.save()

        ticketInput = ""
        showPopover = false
    }
}
