import SwiftUI
import SwiftData
import ApplicationServices

@main
struct TaskManagementApp: App {
    let modelContainer: ModelContainer

    @State private var coordinator: TrackingCoordinator
    @State private var showAccessibilityPermission = false

    init() {
        do {
            let schema = Schema([
                Todo.self,
                Project.self,
                Tag.self,
                JiraLink.self,
                BitbucketLink.self,
                TimeEntry.self,
                IntegrationConfig.self,
                TrackedApplication.self,
                TicketOverride.self,
                ExportRecord.self,
                LearnedPattern.self,
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: config)
            modelContainer = container
            _coordinator = State(initialValue: TrackingCoordinator(modelContainer: container))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(coordinator)
                .overlay {
                    if showAccessibilityPermission {
                        AccessibilityPermissionView {
                            showAccessibilityPermission = false
                            coordinator.startTracking()
                        }
                    }
                }
                .onAppear {
                    seedDataIfNeeded()
                    purgeExpiredData()
                    coordinator.recoverFromCrash()
                    if AXIsProcessTrusted() {
                        coordinator.startTracking()
                    } else {
                        showAccessibilityPermission = true
                    }
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandMenu("Tracking") {
                Button("Toggle Tracking") {
                    if case .tracking = coordinator.state {
                        coordinator.stopTracking()
                    } else {
                        coordinator.startTracking()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Manual Timer") {
                    if coordinator.isManualTimerActive {
                        coordinator.stopManualTimer()
                    } else {
                        coordinator.startManualTimer(label: nil)
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
                .modelContainer(modelContainer)
        } label: {
            Label(
                menuBarText,
                systemImage: coordinator.state == .tracking ? "timer" : "checklist"
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
    }

    private var menuBarText: String {
        if case .tracking = coordinator.state,
           let appName = coordinator.currentAppName {
            return "\(formatElapsed(coordinator.elapsedSeconds)) - \(appName)"
        }
        return "Tasks"
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

    private func seedDataIfNeeded() {
        let service = TimeEntryService(modelContainer: modelContainer)
        Task {
            try? await service.seedTrackedApplicationsIfNeeded()
        }
    }

    private func purgeExpiredData() {
        let service = TimeEntryService(modelContainer: modelContainer)
        Task {
            if let count = try? await service.purgeExpired(), count > 0 {
                print("Purged \(count) expired records")
            }
        }
    }
}
