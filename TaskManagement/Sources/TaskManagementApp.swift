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
                    coordinator.recoverFromCrash()
                    if AXIsProcessTrusted() {
                        coordinator.startTracking()
                    } else {
                        showAccessibilityPermission = true
                    }
                }
        }
        .modelContainer(modelContainer)

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
}
