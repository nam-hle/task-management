import Foundation
import SwiftData
import AppKit

@MainActor
@Observable
final class FirefoxPlugin: TimeTrackingPlugin {
    let id = "firefox"
    let displayName = "Firefox"
    private(set) var status: PluginStatus = .inactive

    private let modelContainer: ModelContainer
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?

    private var currentEntryID: PersistentIdentifier?
    private var lastTitle: String?
    private var lastTicketID: String?
    private var entryStartTime: Date?
    private var isFirefoxActive = false

    private let pollInterval: TimeInterval = 5
    private let minimumDuration: TimeInterval = 10

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - TimeTrackingPlugin

    nonisolated func isAvailable() -> Bool {
        BrowserTabService.isAppInstalled(bundleID: "org.mozilla.firefox")
    }

    func start() async throws {
        guard isAvailable() else {
            status = .unavailable
            return
        }

        status = .active

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                      as? NSRunningApplication,
                  app.bundleIdentifier == "org.mozilla.firefox" else { return }
            Task { @MainActor in
                self.firefoxActivated()
            }
        }

        deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                      as? NSRunningApplication,
                  app.bundleIdentifier == "org.mozilla.firefox" else { return }
            Task { @MainActor in
                self.firefoxDeactivated()
            }
        }

        // Check if Firefox is already active
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier == "org.mozilla.firefox" {
            firefoxActivated()
        }
    }

    func stop() async throws {
        finalizeCurrentEntry()
        stopPolling()

        if let obs = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            activationObserver = nil
        }
        if let obs = deactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            deactivationObserver = nil
        }

        isFirefoxActive = false
        status = .inactive
    }

    // MARK: - Firefox Activation

    private func firefoxActivated() {
        isFirefoxActive = true
        startPolling()
    }

    private func firefoxDeactivated() {
        isFirefoxActive = false
        stopPolling()
        finalizeCurrentEntry()
    }

    // MARK: - Title Polling

    private func startPolling() {
        stopPolling()
        pollTitle()

        pollTimer = Timer.scheduledTimer(
            withTimeInterval: pollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pollTitle()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTitle() {
        guard isFirefoxActive else { return }
        guard let title = BrowserTabService.readFirefoxWindowTitle() else {
            print("[Firefox] Could not read window title")
            return
        }

        let detectedFrom = detectSource(from: title)
        let isRecognizedSource = detectedFrom == "bitbucket"
            || detectedFrom == "jira"
        let ticketID = BrowserTabService.extractTicketID(from: title)
            ?? (isRecognizedSource ? "unassigned" : nil)

        print(
            "[Firefox] title=\"\(title.prefix(80))\" "
            + "ticket=\(ticketID ?? "none") "
            + "source=\(detectedFrom) "
            + "current=\(lastTicketID ?? "none") "
            + "entryID=\(currentEntryID != nil ? "yes" : "nil")"
        )

        guard let ticketID else {
            if currentEntryID != nil {
                print("[Firefox] No ticket — finalizing current entry")
                finalizeCurrentEntry()
            }
            lastTitle = title
            lastTicketID = nil
            return
        }

        // Check if ticket changed
        if ticketID != lastTicketID {
            print(
                "[Firefox] Ticket changed: "
                + "\(lastTicketID ?? "none") → \(ticketID) "
                + "(detectedFrom=\(detectedFrom))"
            )
            finalizeCurrentEntry()

            let service = TimeEntryService(modelContainer: modelContainer)
            let metadata = buildMetadata(
                title: title, detectedFrom: detectedFrom
            )
            Task {
                do {
                    let entryID = try await service.create(
                        applicationName: "Firefox",
                        applicationBundleID: "org.mozilla.firefox",
                        source: .firefox,
                        startTime: Date(),
                        sourcePluginID: "firefox",
                        ticketID: ticketID,
                        contextMetadata: metadata
                    )
                    currentEntryID = entryID
                    entryStartTime = Date()
                    print(
                        "[Firefox] Created entry for \(ticketID)"
                    )
                } catch {
                    print(
                        "[Firefox] Failed to create entry: \(error)"
                    )
                }
            }
        }

        lastTitle = title
        lastTicketID = ticketID
    }

    /// Infer the detection source from the window title pattern
    private func detectSource(from title: String) -> String {
        let lower = title.lowercased()
        // Bitbucket PR titles typically contain "pull request"
        if lower.contains("pull request") || lower.contains("bitbucket") {
            return "bitbucket"
        }
        // Jira titles typically end with "- Jira" or contain "Jira"
        if lower.contains("jira") {
            return "jira"
        }
        return "title"
    }

    private func buildMetadata(title: String, detectedFrom: String) -> String {
        var parts: [String] = []
        parts.append("\"pageTitle\":\"\(escapeJSON(title))\"")
        parts.append("\"parsedFrom\":\"windowTitle\"")
        parts.append("\"detectedFrom\":\"\(detectedFrom)\"")
        return "{\(parts.joined(separator: ","))}"
    }

    // MARK: - Entry Management

    private func finalizeCurrentEntry() {
        guard let entryID = currentEntryID else { return }

        if let start = entryStartTime,
           Date().timeIntervalSince(start) < minimumDuration {
            // Delete short entry
            Task {
                let context = ModelContext(modelContainer)
                if let entry = context.model(for: entryID) as? TimeEntry {
                    context.delete(entry)
                    try? context.save()
                }
            }
        } else {
            let service = TimeEntryService(modelContainer: modelContainer)
            Task {
                try? await service.finalize(entryID: entryID, endTime: Date())
            }
        }

        currentEntryID = nil
        entryStartTime = nil
    }

    // MARK: - Helpers

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
