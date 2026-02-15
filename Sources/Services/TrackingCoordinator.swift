import Foundation
import SwiftData
import AppKit
import ApplicationServices

@MainActor
@Observable
final class TrackingCoordinator {
    private(set) var pluginManager: PluginManager?

    private let modelContainer: ModelContainer
    private var timeEntryService: TimeEntryService?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func setPluginManager(_ manager: PluginManager) {
        self.pluginManager = manager
    }

    // MARK: - Public API

    func startTracking() {
        Task {
            await pluginManager?.startAll()
        }
    }

    func stopTracking() {
        Task {
            await pluginManager?.stopAll()
        }
    }

    func syncPlugins() async {
        await pluginManager?.syncAll()
    }

    func recoverFromCrash() {
        let service = getTimeEntryService()
        Task {
            do {
                let count = try await service.recoverInProgressEntries()
                if count > 0 {
                    print("Recovered \(count) in-progress entries from crash")
                }
            } catch {
                print("Crash recovery failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func getTimeEntryService() -> TimeEntryService {
        if let service = timeEntryService { return service }
        let service = TimeEntryService(modelContainer: modelContainer)
        timeEntryService = service
        return service
    }
}
