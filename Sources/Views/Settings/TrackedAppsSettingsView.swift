import SwiftUI
import SwiftData

struct TrackedAppsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrackedApplication.sortOrder) private var trackedApps: [TrackedApplication]
    @State private var showingAddApp = false

    var body: some View {
        Form {
            Section("Pre-configured") {
                ForEach(trackedApps.filter(\.isPreConfigured)) { app in
                    trackedAppRow(app)
                }
            }

            Section("Additional Apps") {
                ForEach(trackedApps.filter { !$0.isPreConfigured }) { app in
                    trackedAppRow(app)
                }

                Button("Add Application...") {
                    showingAddApp = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddApp) {
            AddTrackedAppSheet()
        }
    }

    private func trackedAppRow(_ app: TrackedApplication) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { app.isEnabled },
                set: { newValue in
                    app.isEnabled = newValue
                    try? modelContext.save()
                }
            )) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(app.name)
                        if app.isBrowser {
                            Text("Browser")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !app.isPreConfigured {
                Button(role: .destructive) {
                    modelContext.delete(app)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AddTrackedAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var runningApps: [(name: String, bundleID: String)] = []
    @State private var selectedBundleID: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Tracked Application")
                .font(.headline)

            List(runningApps, id: \.bundleID, selection: $selectedBundleID) { app in
                HStack {
                    Text(app.name)
                    Spacer()
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(app.bundleID)
            }
            .frame(minHeight: 300)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addSelectedApp() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedBundleID == nil)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear { loadRunningApps() }
    }

    private func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let name = app.localizedName,
                      let bundleID = app.bundleIdentifier else { return nil }
                return (name, bundleID)
            }
            .sorted { $0.0 < $1.0 }
        runningApps = apps
    }

    private func addSelectedApp() {
        guard let bundleID = selectedBundleID,
              let app = runningApps.first(where: { $0.bundleID == bundleID })
        else { return }

        let tracked = TrackedApplication(
            name: app.name,
            bundleIdentifier: app.bundleID,
            isEnabled: true,
            sortOrder: 100
        )
        modelContext.insert(tracked)
        try? modelContext.save()
        dismiss()
    }
}
