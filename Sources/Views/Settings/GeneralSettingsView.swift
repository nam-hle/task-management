import SwiftUI
import SwiftData

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var serviceContainer
    @AppStorage(AppConfig.Keys.idleThresholdSeconds)
    private var idleThreshold = AppConfig.Defaults.idleThresholdSeconds
    @AppStorage(AppConfig.Keys.minimumSwitchDuration)
    private var minSwitchDuration = AppConfig.Defaults.minimumSwitchDuration
    @AppStorage(AppConfig.Keys.autoSaveInterval)
    private var autoSaveInterval = AppConfig.Defaults.autoSaveInterval
    @AppStorage(AppConfig.Keys.browserPollInterval)
    private var browserPollInterval = AppConfig.Defaults.browserPollInterval
    @AppStorage(AppConfig.Keys.browserMinDuration)
    private var browserMinDuration = AppConfig.Defaults.browserMinDuration
    @AppStorage(AppConfig.Keys.wakatimeSyncInterval)
    private var wakatimeSyncInterval = AppConfig.Defaults.wakatimeSyncInterval
    @AppStorage(AppConfig.Keys.dataRetentionDays)
    private var dataRetentionDays = AppConfig.Defaults.dataRetentionDays
    @AppStorage(AppConfig.Keys.todoPurgeDays)
    private var todoPurgeDays = AppConfig.Defaults.todoPurgeDays

    var body: some View {
        Form {
            Section("Idle Detection") {
                HStack {
                    Text("Idle timeout")
                    Spacer()
                    Text(idleThreshold.settingsDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $idleThreshold,
                    in: 60...1800,
                    step: 30
                )
                Text("Time without input before tracking pauses.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Application Switching") {
                HStack {
                    Text("Minimum switch duration")
                    Spacer()
                    Text(minSwitchDuration.settingsDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $minSwitchDuration,
                    in: 5...120,
                    step: 5
                )
                Text("Brief app switches shorter than this are ignored.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Auto-Save") {
                HStack {
                    Text("Save interval")
                    Spacer()
                    Text(autoSaveInterval.settingsDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $autoSaveInterval,
                    in: 15...300,
                    step: 15
                )
                Text("How often in-progress entries are saved to prevent data loss.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Browser Plugins") {
                HStack {
                    Text("Poll interval")
                    Spacer()
                    Text(browserPollInterval.settingsDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $browserPollInterval,
                    in: 2...15,
                    step: 1
                )
                Text("How often browser tabs are checked for ticket info.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                HStack {
                    Text("Minimum browsing duration")
                    Spacer()
                    Text(browserMinDuration.settingsDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $browserMinDuration,
                    in: 3...60,
                    step: 1
                )
                Text("Browser entries shorter than this are discarded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("WakaTime") {
                HStack {
                    Text("Sync interval")
                    Spacer()
                    Text(wakatimeSyncInterval.settingsDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $wakatimeSyncInterval,
                    in: 60...900,
                    step: 30
                )
                Text("How often coding activity is fetched from WakaTime.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Data Retention") {
                HStack {
                    Text("Time entry retention")
                    Spacer()
                    Text("\(Int(dataRetentionDays)) days")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $dataRetentionDays,
                    in: 30...365,
                    step: 1
                )
                Text("Booked time entries older than this are purged.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                HStack {
                    Text("Deleted todo retention")
                    Spacer()
                    Text("\(Int(todoPurgeDays)) days")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $todoPurgeDays,
                    in: 7...90,
                    step: 1
                )
                Text("Soft-deleted todos older than this are permanently removed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Data") {
                Button("Delete All Time Entries", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete All Entries?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllEntries()
            }
        } message: {
            Text("This will permanently delete all time entries. This cannot be undone.")
        }
    }

    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    private func deleteAllEntries() {
        let service = serviceContainer!.makeTimeEntryService()
        Task {
            do {
                try await service.deleteAll()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}
