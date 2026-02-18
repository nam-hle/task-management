import SwiftUI
import SwiftData

struct TicketSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var overrides: [TicketOverride]

    @AppStorage("ticketUnknownPatterns") private var unknownPatternsData = Data()

    @State private var newPattern = ""
    @State private var patternError: String?

    // New override form
    @State private var showAddOverride = false
    @State private var newTicketID = ""
    @State private var newBranch = ""
    @State private var newURLPattern = ""
    @State private var newAppPattern = ""
    @State private var newPriority = 0
    @State private var overrideError: String?

    private var unknownPatterns: [String] {
        (try? JSONDecoder().decode(
            [String].self, from: unknownPatternsData
        )) ?? []
    }

    var body: some View {
        Form {
            overridesSection
            unknownPatternsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Overrides

    private var overridesSection: some View {
        Section {
            if overrides.isEmpty {
                Text("No ticket overrides configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(
                    overrides.sorted { $0.priority > $1.priority }
                ) { override in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(override.ticketID)
                                .font(.headline)
                            if override.priority > 0 {
                                Text("P\(override.priority)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button {
                                modelContext.delete(override)
                                do {
                                    try modelContext.save()
                                } catch {
                                    overrideError = error.localizedDescription
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        if !override.branch.isEmpty {
                            Text("Branch: \(override.branch)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let urlPattern = override.urlPattern,
                           !urlPattern.isEmpty {
                            Text("URL: \(urlPattern)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if let appPattern = override.appNamePattern,
                           !appPattern.isEmpty {
                            Text("App: \(appPattern)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button {
                showAddOverride.toggle()
            } label: {
                Label("Add Override", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if showAddOverride {
                addOverrideForm
            }
        } header: {
            Text("Ticket Override Rules")
        } footer: {
            Text("Override rules assign tickets to entries matching branch, URL, or app patterns.")
                .foregroundStyle(.tertiary)
        }
    }

    private var addOverrideForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ticket ID (e.g. PROJ-123)", text: $newTicketID)
                .textFieldStyle(.roundedBorder)
            TextField("Branch pattern (optional)", text: $newBranch)
                .textFieldStyle(.roundedBorder)
            TextField("URL regex (optional)", text: $newURLPattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            TextField("App name regex (optional)", text: $newAppPattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Stepper("Priority: \(newPriority)", value: $newPriority, in: 0...100)

            if let overrideError {
                Text(overrideError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    resetOverrideForm()
                }
                Button("Save") {
                    saveOverride()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newTicketID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Unknown Patterns

    private var unknownPatternsSection: some View {
        Section {
            ForEach(unknownPatterns, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        removePattern(pattern)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Regex pattern...", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addPattern() }

                Button {
                    addPattern()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(newPattern.trimmingCharacters(
                    in: .whitespaces
                ).isEmpty)
            }

            if let patternError {
                Text(patternError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Unknown Ticket Patterns")
        } footer: {
            Text(
                "Branches matching these regex patterns will be "
                + "grouped as \"Unknown\" instead of inferring a ticket."
            )
            .foregroundStyle(.tertiary)
        }
    }

    private func saveOverride() {
        let ticket = newTicketID.trimmingCharacters(in: .whitespaces)
        guard !ticket.isEmpty else { return }

        // Validate regex patterns
        if !newURLPattern.isEmpty {
            do { _ = try Regex(newURLPattern) }
            catch {
                overrideError = "Invalid URL regex: \(error.localizedDescription)"
                return
            }
        }
        if !newAppPattern.isEmpty {
            do { _ = try Regex(newAppPattern) }
            catch {
                overrideError = "Invalid app regex: \(error.localizedDescription)"
                return
            }
        }

        let override = TicketOverride(
            project: "",
            branch: newBranch.trimmingCharacters(in: .whitespaces),
            ticketID: ticket
        )
        override.urlPattern = newURLPattern.isEmpty ? nil : newURLPattern
        override.appNamePattern = newAppPattern.isEmpty ? nil : newAppPattern
        override.priority = newPriority

        modelContext.insert(override)
        do {
            try modelContext.save()
        } catch {
            overrideError = error.localizedDescription
        }
        resetOverrideForm()
    }

    private func resetOverrideForm() {
        showAddOverride = false
        newTicketID = ""
        newBranch = ""
        newURLPattern = ""
        newAppPattern = ""
        newPriority = 0
        overrideError = nil
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try Regex(trimmed)
        } catch {
            patternError = "Invalid regex: \(error.localizedDescription)"
            return
        }

        patternError = nil
        var current = unknownPatterns
        guard !current.contains(trimmed) else {
            newPattern = ""
            return
        }
        current.append(trimmed)
        if let data = try? JSONEncoder().encode(current) {
            unknownPatternsData = data
        }
        newPattern = ""
    }

    private func removePattern(_ pattern: String) {
        var current = unknownPatterns
        current.removeAll { $0 == pattern }
        if let data = try? JSONEncoder().encode(current) {
            unknownPatternsData = data
        }
    }
}
