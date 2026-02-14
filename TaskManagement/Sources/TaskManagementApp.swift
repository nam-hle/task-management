import SwiftUI
import SwiftData

@main
struct TaskManagementApp: App {
    let modelContainer: ModelContainer

    @State private var timerManager = TimerManager()

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
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(timerManager)
        }
        .modelContainer(modelContainer)

        MenuBarExtra {
            MenuBarView()
                .environment(timerManager)
                .modelContainer(modelContainer)
        } label: {
            Label(timerManager.menuBarText, systemImage: timerManager.isRunning ? "timer" : "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}

@Observable
final class TimerManager {
    var activeEntryID: UUID?
    var activeTodoTitle: String?
    var elapsedSeconds: Int = 0
    var isRunning: Bool = false

    var menuBarText: String {
        if isRunning, let title = activeTodoTitle {
            return "\(formatElapsed(elapsedSeconds)) - \(title)"
        }
        return "Tasks"
    }

    func formatElapsed(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
