import AppKit
import SwiftUI
import SwiftData

@main
struct TaskManagementApp: App {
    let modelContainer: ModelContainer

    @State private var coordinator: TrackingCoordinator
    @State private var pluginManager = PluginManager()
    @State private var jiraService: JiraService
    @State private var logService = LogService()

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
            let log = LogService()
            _logService = State(initialValue: log)
            _jiraService = State(initialValue: JiraService(modelContainer: container, logService: log))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(coordinator)
                .environment(\.jiraService, jiraService)
                .environment(\.logService, logService)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                    setupPlugins()
                    purgeExpiredData()
                    coordinator.recoverFromCrash()
                    coordinator.startTracking()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandMenu("Tracking") {
                Button("Toggle Tracking") {
                    coordinator.startTracking()
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

        Settings {
            SettingsView()
                .modelContainer(modelContainer)
                .environment(coordinator)
                .environment(\.logService, logService)
        }
    }

    private func setupPlugins() {
        let wakaPlugin = WakaTimePlugin(modelContainer: modelContainer)
        let chromePlugin = ChromePlugin(modelContainer: modelContainer)
        let firefoxPlugin = FirefoxPlugin(modelContainer: modelContainer)

        pluginManager.register(wakaPlugin)
        pluginManager.register(chromePlugin)
        pluginManager.register(firefoxPlugin)

        coordinator.setPluginManager(pluginManager)
    }

    private func purgeExpiredData() {
        let service = TimeEntryService(modelContainer: modelContainer)
        Task {
            if let count = try? await service.purgeExpired(), count > 0 {
                logService.log("Purged \(count) expired records")
            }
        }
    }
}
