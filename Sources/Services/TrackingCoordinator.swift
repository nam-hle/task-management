import Foundation
import SwiftData
import AppKit
import ApplicationServices

@MainActor
@Observable
final class TrackingCoordinator {
    private(set) var pluginManager: PluginManager?

    private let modelContainer: ModelContainer
    private let logService: LogService?
    private var timeEntryService: TimeEntryService?

    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        self.modelContainer = modelContainer
        self.logService = logService
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

    func syncPlugins() async {
        await pluginManager?.syncAll()
    }

    func recoverFromCrash() {
        let service = getTimeEntryService()
        Task {
            do {
                let count = try await service.recoverInProgressEntries()
                if count > 0 {
                    logService?.log(
                        "Recovered \(count) in-progress entries from crash",
                        level: .info
                    )
                }
            } catch {
                logService?.log(
                    "Crash recovery failed: \(error)",
                    level: .error
                )
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
