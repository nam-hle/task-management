import AppKit
import SwiftUI
import SwiftData

@main
struct TaskManagementApp: App {
    let modelContainer: ModelContainer

    @State private var coordinator: TrackingCoordinator
    @State private var pluginManager = PluginManager()
    @State private var jiraService: JiraService
    @State private var bitbucketService: BitbucketService
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
            _bitbucketService = State(initialValue: BitbucketService(modelContainer: container, logService: log))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(coordinator)
                .environment(\.jiraService, jiraService)
                .environment(\.bitbucketService, bitbucketService)
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
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
                .environment(coordinator)
                .environment(\.jiraService, jiraService)
                .environment(\.bitbucketService, bitbucketService)
                .environment(\.logService, logService)
        }

        MenuBarExtra("Task Management", systemImage: "checklist.checked") {
            Button("Open Task Management") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") ?? false }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut("o", modifiers: [.command])

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func setupPlugins() {
        let wakaPlugin = WakaTimePlugin(modelContainer: modelContainer, logService: logService)
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
