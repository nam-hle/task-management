import Foundation
import IOKit
import AppKit

@MainActor
final class IdleDetectionService {
    var idleThresholdSeconds: TimeInterval = 300 // 5 minutes default

    private(set) var isMonitoring = false
    private(set) var isIdle = false

    var onIdleStarted: (() -> Void)?
    var onIdleEnded: (() -> Void)?
    var onSleepStarted: (() -> Void)?
    var onWakeUp: (() -> Void)?
    var onScreenLocked: (() -> Void)?
    var onScreenUnlocked: (() -> Void)?

    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    nonisolated var currentIdleSeconds: TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry, &unmanagedDict, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
            let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
            let idleTime = dict["HIDIdleTime"] as? Int64
        else { return 0 }

        return TimeInterval(idleTime) / 1_000_000_000 // nanoseconds to seconds
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Poll for idle state every 30 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }

        // Sleep/wake notifications
        let sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        }
        workspaceObservers.append(sleepObserver)

        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        workspaceObservers.append(wakeObserver)

        // Screen lock/unlock via DistributedNotificationCenter
        let lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenLocked() }
        }
        distributedObservers.append(lockObserver)

        let unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenUnlocked() }
        }
        distributedObservers.append(unlockObserver)

        // Screensaver notifications
        let screensaverStartObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenLocked() }
        }
        distributedObservers.append(screensaverStartObserver)

        let screensaverStopObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenUnlocked() }
        }
        distributedObservers.append(screensaverStopObserver)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        pollTimer?.invalidate()
        pollTimer = nil

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()

        isIdle = false
    }

    private func checkIdleState() {
        let idle = currentIdleSeconds
        let wasIdle = isIdle
        isIdle = idle >= idleThresholdSeconds

        if isIdle && !wasIdle {
            onIdleStarted?()
        } else if !isIdle && wasIdle {
            onIdleEnded?()
        }
    }

    private func handleSleep() {
        isIdle = true
        onSleepStarted?()
    }

    private func handleWake() {
        isIdle = false
        onWakeUp?()
    }

    private func handleScreenLocked() {
        isIdle = true
        onScreenLocked?()
    }

    private func handleScreenUnlocked() {
        isIdle = false
        onScreenUnlocked?()
    }
}
