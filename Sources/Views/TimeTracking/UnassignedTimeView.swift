import SwiftUI
import SwiftData

struct UnassignedTimeView: View {
    let entries: [TimeEntry]

    @Environment(\.modelContext) private var modelContext
    @State private var selectedEntries: Set<PersistentIdentifier> = []
    @State private var bulkTicketInput = ""
    @State private var showBulkAssign = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            entryList
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Unassigned")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(entries.count) entries")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text(formatDuration(totalDuration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            if !selectedEntries.isEmpty {
                Button {
                    showBulkAssign = true
                } label: {
                    Label(
                        "Assign \(selectedEntries.count)",
                        systemImage: "ticket"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showBulkAssign) {
                    bulkAssignPopover
                }
            }
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        ForEach(entries) { entry in
            HStack(spacing: 8) {
                Toggle(
                    isOn: Binding(
                        get: { selectedEntries.contains(entry.persistentModelID) },
                        set: { isSelected in
                            if isSelected {
                                selectedEntries.insert(entry.persistentModelID)
                            } else {
                                selectedEntries.remove(entry.persistentModelID)
                            }
                        }
                    )
                ) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

                sourceIcon(for: entry)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entryTitle(entry))
                        .font(.callout)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(timeRange(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pluginLabel(for: entry))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(entry.formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                AssignEntryButton(entry: entry, modelContext: modelContext)
            }
            .padding(.leading, 24)
        }
    }

    // MARK: - Bulk Assign

    private var bulkAssignPopover: some View {
        VStack(spacing: 8) {
            Text("Assign \(selectedEntries.count) entries")
                .font(.headline)

            TextField("Ticket ID (e.g. PROJ-123)", text: $bulkTicketInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { bulkAssign() }

            HStack {
                Button("Cancel") {
                    showBulkAssign = false
                    bulkTicketInput = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Assign") {
                    bulkAssign()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bulkTicketInput.trimmingCharacters(
                    in: .whitespaces
                ).isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func bulkAssign() {
        let trimmed = bulkTicketInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let ids = Array(selectedEntries)
        let service = TimeEntryService(modelContainer: modelContext.container)
        Task {
            try? await service.assignTicket(entryIDs: ids, ticketID: trimmed)
        }

        selectedEntries.removeAll()
        bulkTicketInput = ""
        showBulkAssign = false
    }

    // MARK: - Helpers

    private var totalDuration: TimeInterval {
        entries.reduce(0.0) { $0 + $1.effectiveDuration }
    }

    private func pluginLabel(for entry: TimeEntry) -> String {
        if entry.sourcePluginID == "wakatime" { return "Code" }
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
        switch entry.sourcePluginID {
        case "chrome": return "Chrome"
        case "firefox": return "Firefox"
        default: return entry.source.label
        }
    }

    private func entryTitle(_ entry: TimeEntry) -> String {
        if entry.sourcePluginID == "wakatime" {
            let meta = parseMetadata(entry.contextMetadata)
            let project = meta["project"] ?? entry.applicationName ?? "Unknown"
            let branch = meta["branch"] ?? ""
            if branch.isEmpty { return project }
            return "\(project) > \(branch)"
        }
        if entry.source == .chrome || entry.source == .firefox {
            if let meta = entry.contextMetadata,
               let title = extractFromMetadata(meta, key: "pageTitle") {
                return title
            }
        }
        return entry.applicationName ?? entry.label ?? "Untitled"
    }

    private func extractFromMetadata(_ json: String, key: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key] as? String else { return nil }
        return value
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
    private func sourceIcon(for entry: TimeEntry) -> some View {
        let label = pluginLabel(for: entry)
        switch label {
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

    private func timeRange(_ entry: TimeEntry) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: entry.startTime)
        if let end = entry.endTime {
            return "\(start) – \(formatter.string(from: end))"
        }
        return "\(start) – now"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}

// MARK: - Per-Entry Assign Button

private struct AssignEntryButton: View {
    let entry: TimeEntry
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
                Text("Assign ticket")
                    .font(.headline)

                TextField("Ticket ID (e.g. PROJ-123)", text: $ticketInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { saveAssignment() }

                HStack {
                    Button("Cancel") {
                        showPopover = false
                        ticketInput = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        saveAssignment()
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

    private func saveAssignment() {
        let trimmed = ticketInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let entryID = entry.persistentModelID
        let service = TimeEntryService(modelContainer: modelContext.container)
        Task {
            try? await service.assignTicket(
                entryIDs: [entryID],
                ticketID: trimmed
            )
        }

        ticketInput = ""
        showPopover = false
    }
}
