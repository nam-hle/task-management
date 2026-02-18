import SwiftUI
import SwiftData

struct UnassignedTimeView: View {
    let entries: [TimeEntry]

    @Environment(\.modelContext) private var modelContext
    @State private var selectedEntries: Set<PersistentIdentifier> = []
    @State private var showBulkAssign = false
    @State private var bulkTicketInput = ""
    @State private var expandedGroups: Set<String> = []
    @State private var errorMessage: String?

    private var groupedEntries: [EntryGroup] {
        var groups: [String: [TimeEntry]] = [:]
        for entry in entries {
            let key = groupKey(for: entry)
            groups[key, default: []].append(entry)
        }
        return groups.map { key, groupEntries in
            let sorted = groupEntries.sorted {
                $0.startTime < $1.startTime
            }
            let duration = sorted.reduce(0.0) {
                $0 + $1.effectiveDuration
            }
            return EntryGroup(
                key: key,
                label: groupLabel(for: sorted.first!),
                icon: groupIcon(for: sorted.first!),
                entries: sorted,
                totalDuration: duration,
                isWakaTime: sorted.first?.sourcePluginID == "wakatime"
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            groupList
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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

    // MARK: - Grouped List

    private var groupList: some View {
        ForEach(groupedEntries) { group in
            if group.isWakaTime {
                wakaTimeProjectGroup(group)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    expandableGroupHeader(group)
                    if expandedGroups.contains(group.key) {
                        ForEach(group.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
    }

    // MARK: - WakaTime Project Group

    private func wakaTimeProjectGroup(
        _ group: EntryGroup
    ) -> some View {
        let branches = wakaTimeBranches(from: group.entries)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                group.icon
                    .font(.caption)

                Text(group.label)
                    .font(.callout.bold())
                    .lineLimit(1)

                Text("\(branches.count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Spacer()

                Text(formatDuration(group.totalDuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 24)
            .padding(.vertical, 4)

            ForEach(branches, id: \.name) { branch in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(branch.name)
                        .font(.callout)
                        .lineLimit(1)

                    Spacer()

                    Text(formatDuration(branch.duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    AssignGroupButton(
                        entryIDs: branch.entryIDs,
                        modelContext: modelContext
                    )
                }
                .padding(.leading, 48)
                .padding(.vertical, 2)
            }
        }
    }

    private struct BranchInfo {
        let name: String
        let duration: TimeInterval
        let entryIDs: [PersistentIdentifier]
    }

    private func wakaTimeBranches(
        from entries: [TimeEntry]
    ) -> [BranchInfo] {
        var grouped: [String: (TimeInterval, [PersistentIdentifier])] = [:]
        for entry in entries {
            let meta = parseMetadata(entry.contextMetadata)
            let branch = meta["branch"] ?? "unknown"
            let existing = grouped[branch] ?? (0, [])
            grouped[branch] = (
                existing.0 + entry.effectiveDuration,
                existing.1 + [entry.persistentModelID]
            )
        }
        return grouped.map { name, info in
            BranchInfo(
                name: name,
                duration: info.0,
                entryIDs: info.1
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    // MARK: - Expandable Group

    private func expandableGroupHeader(
        _ group: EntryGroup
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                if expandedGroups.contains(group.key) {
                    expandedGroups.remove(group.key)
                } else {
                    expandedGroups.insert(group.key)
                }
            } label: {
                Image(
                    systemName: expandedGroups.contains(group.key)
                        ? "chevron.down" : "chevron.right"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            }
            .buttonStyle(.plain)

            group.icon
                .font(.caption)

            Text(group.label)
                .font(.callout.bold())
                .lineLimit(1)

            Text("\(group.entries.count)")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(Capsule())

            Spacer()

            Text(formatDuration(group.totalDuration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 24)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack(spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: {
                        selectedEntries.contains(
                            entry.persistentModelID
                        )
                    },
                    set: { isSelected in
                        if isSelected {
                            selectedEntries.insert(
                                entry.persistentModelID
                            )
                        } else {
                            selectedEntries.remove(
                                entry.persistentModelID
                            )
                        }
                    }
                )
            ) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(entryTitle(entry))
                    .font(.callout)
                    .lineLimit(1)
                Text(timeRange(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.formattedDuration)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            AssignEntryButton(
                entry: entry, modelContext: modelContext
            )
        }
        .padding(.leading, 48)
    }

    // MARK: - Bulk Assign

    private var bulkAssignPopover: some View {
        VStack(spacing: 8) {
            Text("Assign \(selectedEntries.count) entries")
                .font(.headline)

            TextField(
                "Ticket ID (e.g. PROJ-123)", text: $bulkTicketInput
            )
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
                .disabled(
                    bulkTicketInput
                        .trimmingCharacters(in: .whitespaces)
                        .isEmpty
                )
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func bulkAssign() {
        let trimmed = bulkTicketInput
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let ids = Array(selectedEntries)
        let service = TimeEntryService(
            modelContainer: modelContext.container
        )
        Task {
            do {
                try await service.assignTicket(
                    entryIDs: ids, ticketID: trimmed
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        selectedEntries.removeAll()
        bulkTicketInput = ""
        showBulkAssign = false
    }

    // MARK: - Grouping

    private func groupKey(for entry: TimeEntry) -> String {
        if entry.sourcePluginID == "wakatime" {
            let meta = parseMetadata(entry.contextMetadata)
            let project = meta["project"] ?? "unknown"
            return "waka:\(project)"
        }
        if let pluginID = entry.sourcePluginID,
           !pluginID.isEmpty
        {
            return "plugin:\(pluginID)"
        }
        if let appName = entry.applicationName, !appName.isEmpty {
            return "app:\(appName)"
        }
        return "source:\(entry.source.rawValue)"
    }

    private func groupLabel(for entry: TimeEntry) -> String {
        if entry.sourcePluginID == "wakatime" {
            let meta = parseMetadata(entry.contextMetadata)
            return meta["project"] ?? "Unknown Project"
        }
        if let pluginID = entry.sourcePluginID {
            switch pluginID {
            case "chrome": return "Google Chrome"
            case "firefox": return "Firefox"
            default: return pluginID
            }
        }
        if let appName = entry.applicationName, !appName.isEmpty {
            return appName
        }
        return entry.source.label
    }

    @ViewBuilder
    private func groupIcon(
        for entry: TimeEntry
    ) -> some View {
        if entry.sourcePluginID == "wakatime" {
            Image(
                systemName: "chevronleft.forwardslash.chevronright"
            )
            .foregroundStyle(.green)
        } else if entry.sourcePluginID == "chrome"
            || entry.applicationBundleID == "com.google.Chrome"
        {
            Image(systemName: "globe")
                .foregroundStyle(.blue)
        } else if entry.sourcePluginID == "firefox"
            || entry.applicationBundleID == "org.mozilla.firefox"
        {
            Image(systemName: "globe")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "macwindow")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var totalDuration: TimeInterval {
        entries.reduce(0.0) { $0 + $1.effectiveDuration }
    }

    private func entryTitle(_ entry: TimeEntry) -> String {
        let meta = parseMetadata(entry.contextMetadata)
        if let title = meta["pageTitle"], !title.isEmpty {
            return title
        }
        return entry.label ?? entry.applicationName ?? "Untitled"
    }

    private func parseMetadata(
        _ json: String?
    ) -> [String: String] {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any]
        else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if let str = value as? String { result[key] = str }
        }
        return result
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

    private func formatDuration(
        _ interval: TimeInterval
    ) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}

// MARK: - Entry Group

private struct EntryGroup: Identifiable {
    let key: String
    let label: String
    let icon: AnyView
    let entries: [TimeEntry]
    let totalDuration: TimeInterval
    let isWakaTime: Bool

    var id: String { key }

    init(
        key: String,
        label: String,
        icon: some View,
        entries: [TimeEntry],
        totalDuration: TimeInterval,
        isWakaTime: Bool = false
    ) {
        self.key = key
        self.label = label
        self.icon = AnyView(icon)
        self.entries = entries
        self.totalDuration = totalDuration
        self.isWakaTime = isWakaTime
    }
}

// MARK: - Assign Group Button

private struct AssignGroupButton: View {
    let entryIDs: [PersistentIdentifier]
    let modelContext: ModelContext

    @State private var showPopover = false
    @State private var ticketInput = ""
    @State private var errorMessage: String?

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Text("Assign")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .popover(isPresented: $showPopover) {
            VStack(spacing: 8) {
                Text("Assign \(entryIDs.count) entries")
                    .font(.headline)

                TextField(
                    "Ticket ID (e.g. PROJ-123)",
                    text: $ticketInput
                )
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
                    .disabled(
                        ticketInput
                            .trimmingCharacters(in: .whitespaces)
                            .isEmpty
                    )
                }
            }
            .padding()
        }
    }

    private func saveAssignment() {
        let trimmed = ticketInput
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let service = TimeEntryService(
            modelContainer: modelContext.container
        )
        Task {
            do {
                try await service.assignTicket(
                    entryIDs: entryIDs, ticketID: trimmed
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        ticketInput = ""
        showPopover = false
    }
}

// MARK: - Per-Entry Assign Button

private struct AssignEntryButton: View {
    let entry: TimeEntry
    let modelContext: ModelContext

    @State private var showPopover = false
    @State private var ticketInput = ""
    @State private var errorMessage: String?

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Text("Assign")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .popover(isPresented: $showPopover) {
            VStack(spacing: 8) {
                Text("Assign ticket")
                    .font(.headline)

                TextField(
                    "Ticket ID (e.g. PROJ-123)",
                    text: $ticketInput
                )
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
                    .disabled(
                        ticketInput
                            .trimmingCharacters(in: .whitespaces)
                            .isEmpty
                    )
                }
            }
            .padding()
        }
    }

    private func saveAssignment() {
        let trimmed = ticketInput
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let entryID = entry.persistentModelID
        let service = TimeEntryService(
            modelContainer: modelContext.container
        )
        Task {
            do {
                try await service.assignTicket(
                    entryIDs: [entryID],
                    ticketID: trimmed
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        ticketInput = ""
        showPopover = false
    }
}
