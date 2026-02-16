import Foundation
import SwiftData
import AppKit

@MainActor
@Observable
final class ChromePlugin: TimeTrackingPlugin {
    let id = "chrome"
    let displayName = "Chrome"
    private(set) var status: PluginStatus = .inactive

    private let modelContainer: ModelContainer
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?

    private var currentEntryID: PersistentIdentifier?
    private var lastTabInfo: BrowserTabInfo?
    private var lastTicketID: String?
    private var entryStartTime: Date?
    private var isChromeActive = false

    private let pollInterval: TimeInterval = 5
    private let minimumDuration: TimeInterval = 10

    // Bitbucket credentials cache
    private var bbToken: String?
    private var bbCredentialsLoaded = false
    // Cache PR lookups to avoid repeated API calls
    private var prCache: [String: BitbucketPRDetail] = [:]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - TimeTrackingPlugin

    nonisolated func isAvailable() -> Bool {
        BrowserTabService.isAppInstalled(bundleID: "com.google.Chrome")
    }

    func start() async throws {
        guard isAvailable() else {
            status = .unavailable
            return
        }

        status = .active
        loadBitbucketCredentials()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                      as? NSRunningApplication,
                  app.bundleIdentifier == "com.google.Chrome" else { return }
            Task { @MainActor in
                self.chromeActivated()
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
                  app.bundleIdentifier == "com.google.Chrome" else { return }
            Task { @MainActor in
                self.chromeDeactivated()
            }
        }

        // Check if Chrome is already active
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier == "com.google.Chrome" {
            chromeActivated()
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

        isChromeActive = false
        status = .inactive
    }

    // MARK: - Chrome Activation

    private func chromeActivated() {
        isChromeActive = true
        startPolling()
    }

    private func chromeDeactivated() {
        isChromeActive = false
        stopPolling()
        finalizeCurrentEntry()
    }

    // MARK: - Tab Polling

    private func startPolling() {
        stopPolling()
        // Poll immediately
        Task { await pollTab() }

        pollTimer = Timer.scheduledTimer(
            withTimeInterval: pollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pollTab()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTab() async {
        guard isChromeActive else { return }
        guard let tabInfo = await BrowserTabService.readChromeTab() else { return }

        let resolution = await resolveTicket(tabInfo: tabInfo)

        // Only create/update entry if we detected a Jira or Bitbucket page
        guard let resolution else {
            // Not a Jira/Bitbucket page — finalize any existing entry
            if currentEntryID != nil {
                finalizeCurrentEntry()
            }
            lastTabInfo = tabInfo
            lastTicketID = nil
            return
        }

        // Check if tab changed (different ticket or significantly different page)
        if resolution.ticketID != lastTicketID {
            finalizeCurrentEntry()

            // Create new entry for this ticket
            let service = TimeEntryService(modelContainer: modelContainer)
            let metadata = buildMetadata(
                tabInfo: tabInfo, detectedFrom: resolution.detectedFrom
            )
            do {
                let entryID = try await service.create(
                    applicationName: "Google Chrome",
                    applicationBundleID: "com.google.Chrome",
                    source: .chrome,
                    startTime: Date(),
                    sourcePluginID: "chrome",
                    ticketID: resolution.ticketID,
                    contextMetadata: metadata
                )
                currentEntryID = entryID
                entryStartTime = Date()
            } catch {
                print("Chrome plugin: Failed to create entry: \(error)")
            }
        }

        lastTabInfo = tabInfo
        lastTicketID = resolution.ticketID
    }

    // MARK: - Ticket Resolution

    private struct TicketResolution {
        let ticketID: String
        let detectedFrom: String  // "jira", "bitbucket", or "title"
    }

    private func resolveTicket(tabInfo: BrowserTabInfo) async -> TicketResolution? {
        // 1. Check Jira URL
        if let url = tabInfo.url,
           let ticket = BrowserTabService.extractJiraTicketFromURL(url) {
            return TicketResolution(ticketID: ticket, detectedFrom: "jira")
        }

        // 2. Check Bitbucket PR URL
        if let url = tabInfo.url,
           let prRef = BrowserTabService.parseBitbucketPRURL(url) {
            let detail = await fetchOrCachePR(ref: prRef)
            if let detail {
                print(
                    "[Chrome] Bitbucket PR: "
                    + "title=\"\(detail.title)\" "
                    + "branch=\(detail.sourceBranch) "
                    + "creator=\(detail.creator ?? "unknown")"
                )
            }
            let ticketID = detail?.ticketID ?? "unassigned"
            return TicketResolution(
                ticketID: ticketID, detectedFrom: "bitbucket"
            )
        }

        // 3. Try extracting ticket from page title
        if let ticket = BrowserTabService.extractTicketID(from: tabInfo.title) {
            return TicketResolution(ticketID: ticket, detectedFrom: "title")
        }

        return nil
    }

    private func fetchOrCachePR(ref: BitbucketPRRef) async -> BitbucketPRDetail? {
        let cacheKey = "\(ref.projectKey)/\(ref.repoSlug)/\(ref.prNumber)"
        if let cached = prCache[cacheKey] {
            return cached
        }

        guard let token = bbToken else { return nil }

        let detail = await BrowserTabService.fetchBitbucketPR(
            ref: ref, token: token
        )
        if let detail {
            prCache[cacheKey] = detail
        }
        return detail
    }

    // MARK: - Entry Management

    private func finalizeCurrentEntry() {
        guard let entryID = currentEntryID else { return }

        // Skip entries shorter than minimum duration
        if let start = entryStartTime,
           Date().timeIntervalSince(start) < minimumDuration {
            // Delete short entry
            Task {
                let context = ModelContext(self.modelContainer)
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

    private func loadBitbucketCredentials() {
        guard !bbCredentialsLoaded else { return }
        bbCredentialsLoaded = true

        let context = ModelContext(modelContainer)
        let bbType = IntegrationType.bitbucket
        let predicate = #Predicate<IntegrationConfig> { $0.type == bbType }
        let descriptor = FetchDescriptor<IntegrationConfig>(predicate: predicate)

        if let config = try? context.fetch(descriptor).first,
           config.isEnabled {
            bbToken = KeychainService.retrieve(key: "bitbucket_token")
        }
    }

    private func buildMetadata(
        tabInfo: BrowserTabInfo, detectedFrom: String
    ) -> String {
        var parts: [String] = []
        parts.append("\"pageTitle\":\"\(escapeJSON(tabInfo.title))\"")
        if let url = tabInfo.url {
            parts.append("\"pageURL\":\"\(escapeJSON(url))\"")
        }
        parts.append("\"detectedFrom\":\"\(detectedFrom)\"")
        return "{\(parts.joined(separator: ","))}"
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
