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
    private var lastTabInfo: BrowserTabInfo?
    private var lastTicketID: String?
    private var entryStartTime: Date?
    private var isFirefoxActive = false

    private var pollInterval: TimeInterval { AppConfig.browserPollInterval }
    private var minimumDuration: TimeInterval { AppConfig.browserMinDuration }

    // Bitbucket credentials cache
    private var bbToken: String?
    private var bbCredentialsLoaded = false
    // Cache PR lookups to avoid repeated API calls
    private var prCache: [String: BitbucketPRDetail] = [:]

    private let logService: LogService?

    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        self.modelContainer = modelContainer
        self.logService = logService
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
        loadBitbucketCredentials()

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

    // MARK: - Tab Polling

    private func startPolling() {
        stopPolling()
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
        guard isFirefoxActive else { return }
        guard let tabInfo = BrowserTabService.readFirefoxTab() else {
            logService?.log("[Firefox] Could not read tab info", level: .error)
            return
        }

        let resolution = await resolveTicket(tabInfo: tabInfo)

        logService?.log(
            "[Firefox] title=\"\(tabInfo.title.prefix(80))\" "
            + "url=\(tabInfo.url ?? "nil") "
            + "ticket=\(resolution?.ticketID ?? "none") "
            + "source=\(resolution?.detectedFrom ?? "none") "
            + "current=\(lastTicketID ?? "none") "
            + "entryID=\(currentEntryID != nil ? "yes" : "nil")"
        )

        guard let resolution else {
            if currentEntryID != nil {
                logService?.log("[Firefox] No ticket — finalizing current entry")
                finalizeCurrentEntry()
            }
            lastTabInfo = tabInfo
            lastTicketID = nil
            return
        }

        if resolution.ticketID != lastTicketID {
            logService?.log(
                "[Firefox] Ticket changed: "
                + "\(lastTicketID ?? "none") → \(resolution.ticketID) "
                + "(detectedFrom=\(resolution.detectedFrom))"
            )
            finalizeCurrentEntry()

            let service = TimeEntryService(modelContainer: modelContainer)
            let metadata = buildMetadata(
                tabInfo: tabInfo, detectedFrom: resolution.detectedFrom
            )
            do {
                let entryID = try await service.create(
                    applicationName: "Firefox",
                    applicationBundleID: "org.mozilla.firefox",
                    source: .firefox,
                    startTime: Date(),
                    sourcePluginID: "firefox",
                    ticketID: resolution.ticketID,
                    contextMetadata: metadata
                )
                currentEntryID = entryID
                entryStartTime = Date()
                logService?.log("[Firefox] Created entry for \(resolution.ticketID)")
            } catch {
                logService?.log(
                    "[Firefox] Failed to create entry: \(error)",
                    level: .error
                )
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

    private func resolveTicket(
        tabInfo: BrowserTabInfo
    ) async -> TicketResolution? {
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
                logService?.log(
                    "[Firefox] Bitbucket PR: "
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
        if let ticket = BrowserTabService.extractTicketID(
            from: tabInfo.title
        ) {
            return TicketResolution(ticketID: ticket, detectedFrom: "title")
        }

        return nil
    }

    private func fetchOrCachePR(
        ref: BitbucketPRRef
    ) async -> BitbucketPRDetail? {
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

        if let start = entryStartTime,
           Date().timeIntervalSince(start) < minimumDuration {
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

    private func loadBitbucketCredentials() {
        guard !bbCredentialsLoaded else { return }
        bbCredentialsLoaded = true

        let context = ModelContext(modelContainer)
        let bbType = IntegrationType.bitbucket
        let predicate = #Predicate<IntegrationConfig> { $0.type == bbType }
        let descriptor = FetchDescriptor<IntegrationConfig>(
            predicate: predicate
        )

        if let config = try? context.fetch(descriptor).first,
           config.isEnabled {
            bbToken = try? KeychainService.retrieve(key: "bitbucket_token")
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
