import SwiftUI

struct TicketSettingsView: View {
    let wakaTimeService: WakaTimeService

    @Binding var excludedProjectsData: Data
    @Binding var unknownPatternsData: Data

    @Environment(\.dismiss) private var dismiss

    @State private var newPattern = ""
    @State private var patternError: String?

    private var excludedProjects: Set<String> {
        get {
            (try? JSONDecoder().decode(
                [String].self, from: excludedProjectsData
            )).map(Set.init) ?? []
        }
    }

    private var unknownPatterns: [String] {
        get {
            (try? JSONDecoder().decode(
                [String].self, from: unknownPatternsData
            )) ?? []
        }
    }

    private var allProjects: [String] {
        let projects = Set(wakaTimeService.branches.map(\.project))
        return projects.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Ticket Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                excludedProjectsSection
                unknownPatternsSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 400)
    }

    // MARK: - Excluded Projects

    private var excludedProjectsSection: some View {
        Section {
            if allProjects.isEmpty {
                Text("No projects found in today's data")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allProjects, id: \.self) { project in
                    Toggle(project, isOn: projectBinding(for: project))
                }
            }
        } header: {
            Text("Excluded Projects")
        } footer: {
            Text("Toggled projects will be hidden from the Tickets view.")
                .foregroundStyle(.tertiary)
        }
    }

    private func projectBinding(for project: String) -> Binding<Bool> {
        Binding(
            get: { excludedProjects.contains(project) },
            set: { isExcluded in
                var current = excludedProjects
                if isExcluded {
                    current.insert(project)
                } else {
                    current.remove(project)
                }
                if let data = try? JSONEncoder().encode(Array(current)) {
                    excludedProjectsData = data
                }
            }
        )
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

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Validate regex
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
