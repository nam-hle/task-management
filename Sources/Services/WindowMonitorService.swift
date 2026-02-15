import AppKit
import ApplicationServices

struct ApplicationInfo {
    let name: String
    let bundleIdentifier: String
    let pid: pid_t
    let windowTitle: String?
    let timestamp: Date
}

@MainActor
final class WindowMonitorService {
    private(set) var isTracking = false
    var onApplicationChanged: ((ApplicationInfo) -> Void)?

    private var lastAppInfo: ApplicationInfo?
    private var workspaceObserver: NSObjectProtocol?

    func startMonitoring() {
        guard !isTracking else { return }
        isTracking = true

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor in
                self.handleAppActivation(app)
            }
        }

        // Capture initial active app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            handleAppActivation(frontApp)
        }
    }

    func stopMonitoring() {
        guard isTracking else { return }
        isTracking = false

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        lastAppInfo = nil
    }

    func currentApplication() -> ApplicationInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return applicationInfo(from: app)
    }

    private func handleAppActivation(_ app: NSRunningApplication) {
        let info = applicationInfo(from: app)

        // Skip if same app
        if let last = lastAppInfo, last.bundleIdentifier == info.bundleIdentifier {
            return
        }

        lastAppInfo = info
        onApplicationChanged?(info)
    }

    private func applicationInfo(from app: NSRunningApplication) -> ApplicationInfo {
        let name = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? ""
        let pid = app.processIdentifier
        let title = windowTitle(for: pid)

        return ApplicationInfo(
            name: name,
            bundleIdentifier: bundleID,
            pid: pid,
            windowTitle: title,
            timestamp: Date()
        )
    }

    private func windowTitle(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow
        )
        guard result == .success, let window = focusedWindow else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue
        )
        guard titleResult == .success, let title = titleValue as? String else { return nil }
        return title
    }
}
