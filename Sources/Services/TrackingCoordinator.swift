import Foundation
import SwiftData
import AppKit
import ApplicationServices

@MainActor
@Observable
final class TrackingCoordinator {
    private(set) var pluginManager: PluginManager?
    private(set) var isManualTimerActive = false

    private let modelContainer: ModelContainer
    private var timeEntryService: TimeEntryService?

    // Manual timer state
    private var manualEntryID: PersistentIdentifier?
    private var manualTimerStart: Date?
    private var manualTimerLabel: String?
    private var elapsedTimer: Timer?

    var manualTimerElapsed: Int {
        guard isManualTimerActive, let start = manualTimerStart else { return 0 }
        return Int(Date().timeIntervalSince(start))
    }

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

    func startManualTimer(label: String?, todoID: PersistentIdentifier? = nil) {
        isManualTimerActive = true
        manualTimerLabel = label

        let service = getTimeEntryService()
        Task {
            do {
                let entryID = try await service.create(
                    todoID: todoID,
                    source: .timer,
                    startTime: Date(),
                    label: label
                )
                manualEntryID = entryID
                manualTimerStart = Date()
                startElapsedTimer()
            } catch {
                print("Failed to start manual timer: \(error)")
            }
        }
    }

    func stopManualTimer() {
        guard isManualTimerActive else { return }
        isManualTimerActive = false

        if let entryID = manualEntryID {
            let service = getTimeEntryService()
            Task {
                try? await service.finalize(entryID: entryID, endTime: Date())
            }
        }
        manualEntryID = nil
        manualTimerStart = nil
        manualTimerLabel = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
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

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(
            withTimeInterval: 1, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.manualTimerElapsed
            }
        }
    }
}
