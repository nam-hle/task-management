import Foundation
import SwiftData
import AppKit
import ApplicationServices

@MainActor
@Observable
final class TrackingCoordinator {
    private(set) var state: TrackingState = .idle
    private(set) var currentAppName: String?
    private(set) var currentEntryID: PersistentIdentifier?
    private(set) var trackingStartTime: Date?
    private(set) var isManualTimerActive = false

    var elapsedSeconds: Int {
        guard let start = trackingStartTime else { return 0 }
        return Int(Date().timeIntervalSince(start))
    }

    // Configurable thresholds
    var minimumSwitchDuration: TimeInterval = 30
    var autoSaveInterval: TimeInterval = 60

    private let modelContainer: ModelContainer
    private let windowMonitor = WindowMonitorService()
    private let idleDetection = IdleDetectionService()
    private var timeEntryService: TimeEntryService?

    private var autoSaveTimer: Timer?
    private var midnightTimer: Timer?
    private var elapsedTimer: Timer?
    private var lastSwitchTime: Date?
    private var pendingAppInfo: ApplicationInfo?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        setupCallbacks()
    }

    // MARK: - Public API

    func startTracking() {
        guard AXIsProcessTrusted() else {
            state = .permissionRequired
            return
        }
        beginTracking()
    }

    func stopTracking() {
        guard case .tracking = state else { return }
        finalizeCurrentEntry()
        windowMonitor.stopMonitoring()
        idleDetection.stopMonitoring()
        stopTimers()
        state = .idle
        currentAppName = nil
        trackingStartTime = nil
    }

    func startManualTimer(label: String?, todoID: PersistentIdentifier? = nil) {
        // Stop any existing entry
        finalizeCurrentEntry()

        isManualTimerActive = true

        // Suppress auto-tracking while manual timer is active
        if case .tracking = state {
            windowMonitor.stopMonitoring()
        }

        let service = getTimeEntryService()
        Task {
            do {
                let entryID = try await service.create(
                    todoID: todoID,
                    source: .manual,
                    startTime: Date(),
                    label: label
                )
                currentEntryID = entryID
                trackingStartTime = Date()
                currentAppName = label ?? "Manual Timer"
                state = .tracking
                startElapsedTimer()
                startAutoSaveTimer()
            } catch {
                print("Failed to start manual timer: \(error)")
            }
        }
    }

    func stopManualTimer() {
        guard isManualTimerActive else { return }
        isManualTimerActive = false
        finalizeCurrentEntry()

        // Resume auto-tracking if it was active
        if windowMonitor.isTracking {
            // Already tracking, just clear manual state
        } else if case .tracking = state {
            windowMonitor.startMonitoring()
        }

        state = .idle
        currentAppName = nil
        trackingStartTime = nil
    }

    func pause(reason: PauseReason) {
        guard case .tracking = state else { return }
        finalizeCurrentEntry()
        state = .paused(reason: reason)
    }

    func resume() {
        guard case .paused = state else { return }
        state = .tracking

        // Re-capture current app
        if let appInfo = windowMonitor.currentApplication() {
            handleAppSwitch(appInfo)
        }
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

    private func beginTracking() {
        state = .tracking
        windowMonitor.startMonitoring()
        idleDetection.startMonitoring()
        startAutoSaveTimer()
        scheduleMidnightSplit()
        startElapsedTimer()
    }

    private func setupCallbacks() {
        windowMonitor.onApplicationChanged = { [weak self] appInfo in
            Task { @MainActor in
                self?.handleAppSwitch(appInfo)
            }
        }

        idleDetection.onIdleStarted = { [weak self] in
            Task { @MainActor in
                self?.pause(reason: .systemIdle)
            }
        }

        idleDetection.onIdleEnded = { [weak self] in
            Task { @MainActor in
                self?.resume()
            }
        }

        idleDetection.onSleepStarted = { [weak self] in
            Task { @MainActor in
                self?.pause(reason: .systemSleep)
            }
        }

        idleDetection.onWakeUp = { [weak self] in
            Task { @MainActor in
                self?.resume()
            }
        }

        idleDetection.onScreenLocked = { [weak self] in
            Task { @MainActor in
                self?.pause(reason: .screenLocked)
            }
        }

        idleDetection.onScreenUnlocked = { [weak self] in
            Task { @MainActor in
                self?.resume()
            }
        }
    }

    private func handleAppSwitch(_ appInfo: ApplicationInfo) {
        guard !isManualTimerActive else { return }
        guard case .tracking = state else { return }

        // Check minimum switch duration
        if let lastSwitch = lastSwitchTime,
           Date().timeIntervalSince(lastSwitch) < minimumSwitchDuration {
            pendingAppInfo = appInfo
            return
        }

        // Finalize previous entry and create new one for the active app
        let service = getTimeEntryService()
        Task {
            // Finalize previous entry
            finalizeCurrentEntry()

            // Create new entry for the active app
            do {
                let entryID = try await service.create(
                    applicationName: appInfo.name,
                    applicationBundleID: appInfo.bundleIdentifier,
                    source: .autoDetected,
                    startTime: appInfo.timestamp
                )
                currentEntryID = entryID
                trackingStartTime = appInfo.timestamp
                currentAppName = appInfo.name
                lastSwitchTime = appInfo.timestamp
            } catch {
                print("Failed to create time entry: \(error)")
            }
        }
    }

    private func isAppTracked(bundleID: String) async -> Bool {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<TrackedApplication> {
            $0.bundleIdentifier == bundleID && $0.isEnabled == true
        }
        let descriptor = FetchDescriptor<TrackedApplication>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    private func finalizeCurrentEntry() {
        guard let entryID = currentEntryID else { return }
        let service = getTimeEntryService()
        let now = Date()
        Task {
            try? await service.finalize(entryID: entryID, endTime: now)
        }
        currentEntryID = nil
    }

    private func getTimeEntryService() -> TimeEntryService {
        if let service = timeEntryService { return service }
        let service = TimeEntryService(modelContainer: modelContainer)
        timeEntryService = service
        return service
    }

    // MARK: - Timers

    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: autoSaveInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performAutoSave()
            }
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(
            withTimeInterval: 1, repeats: true
        ) { [weak self] _ in
            // Just triggers @Observable update via elapsedSeconds computed property
            Task { @MainActor in
                _ = self?.elapsedSeconds
            }
        }
    }

    private func performAutoSave() {
        guard let entryID = currentEntryID else { return }
        let service = getTimeEntryService()
        Task {
            try? await service.autoSave(entryID: entryID)
        }
    }

    private func scheduleMidnightSplit() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: Date())!
        )
        let interval = tomorrow.timeIntervalSinceNow

        midnightTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMidnightSplit()
            }
        }
    }

    private func handleMidnightSplit() {
        guard let entryID = currentEntryID else {
            scheduleMidnightSplit()
            return
        }
        let service = getTimeEntryService()
        Task {
            if let newID = try? await service.splitAtMidnight(entryID: entryID) {
                currentEntryID = newID
                trackingStartTime = Calendar.current.startOfDay(for: Date())
            }
            scheduleMidnightSplit()
        }
    }

    private func stopTimers() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
