import Foundation
import SwiftData
import AppKit

struct BrowserConfig {
    let id: String
    let displayName: String
    let bundleID: String
    let applicationName: String
    let source: EntrySource

    static let chrome = BrowserConfig(
        id: "chrome",
        displayName: "Chrome",
        bundleID: "com.google.Chrome",
        applicationName: "Google Chrome",
        source: .chrome
    )

    static let firefox = BrowserConfig(
        id: "firefox",
        displayName: "Firefox",
        bundleID: "org.mozilla.firefox",
        applicationName: "Firefox",
        source: .firefox
    )
}

@MainActor
@Observable
class BrowserTabTrackingPlugin: TimeTrackingPlugin {
    let id: String
    let displayName: String
    private(set) var status: PluginStatus = .inactive

    let config: BrowserConfig
    let modelContainer: ModelContainer
    let logService: LogService?

    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?

    private var currentEntryID: PersistentIdentifier?
    private var lastTabInfo: BrowserTabInfo?
    private var lastTicketID: String?
    private var entryStartTime: Date?
    private var isBrowserActive = false

    private var pollInterval: TimeInterval { AppConfig.browserPollInterval }
    private var minimumDuration: TimeInterval { AppConfig.browserMinDuration }

    private var bbToken: String?
    private var bbCredentialsLoaded = false
    private var prCache: [String: BitbucketPRDetail] = [:]

    init(
        config: BrowserConfig,
        modelContainer: ModelContainer,
        logService: LogService? = nil
    ) {
        self.config = config
        self.id = config.id
        self.displayName = config.displayName
        self.modelContainer = modelContainer
        self.logService = logService
    }

    // MARK: - Override Point

    func readCurrentTab() async -> BrowserTabInfo? {
        fatalError("Subclasses must override readCurrentTab()")
    }

    // MARK: - TimeTrackingPlugin

    nonisolated func isAvailable() -> Bool {
        BrowserTabService.isAppInstalled(bundleID: config.bundleID)
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
                  let app = notification.userInfo?[
                      NSWorkspace.applicationUserInfoKey
                  ] as? NSRunningApplication,
                  app.bundleIdentifier == self.config.bundleID
            else { return }
            Task { @MainActor in
                self.browserActivated()
            }
        }

        deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[
                      NSWorkspace.applicationUserInfoKey
                  ] as? NSRunningApplication,
                  app.bundleIdentifier == self.config.bundleID
            else { return }
            Task { @MainActor in
                self.browserDeactivated()
            }
        }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier == config.bundleID {
            browserActivated()
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

        isBrowserActive = false
        status = .inactive
    }

    // MARK: - Browser Activation

    private func browserActivated() {
        isBrowserActive = true
        startPolling()
    }

    private func browserDeactivated() {
        isBrowserActive = false
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
        let prefix = "[\(config.displayName)]"
        guard isBrowserActive else { return }
        guard let tabInfo = await readCurrentTab() else {
            logService?.log(
                "\(prefix) Could not read tab info", level: .error
            )
            return
        }

        let resolution = await resolveTicket(tabInfo: tabInfo)

        logService?.log(
            "\(prefix) title=\"\(tabInfo.title.prefix(80))\" "
            + "url=\(tabInfo.url ?? "nil") "
            + "ticket=\(resolution?.ticketID ?? "none") "
            + "source=\(resolution?.detectedFrom ?? "none") "
            + "current=\(lastTicketID ?? "none") "
            + "entryID=\(currentEntryID != nil ? "yes" : "nil")"
        )

        guard let resolution else {
            if currentEntryID != nil {
                logService?.log(
                    "\(prefix) No ticket — finalizing current entry"
                )
                finalizeCurrentEntry()
            }
            lastTabInfo = tabInfo
            lastTicketID = nil
            return
        }

        if resolution.ticketID != lastTicketID {
            logService?.log(
                "\(prefix) Ticket changed: "
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
                    applicationName: config.applicationName,
                    applicationBundleID: config.bundleID,
                    source: config.source,
                    startTime: Date(),
                    sourcePluginID: config.id,
                    ticketID: resolution.ticketID,
                    contextMetadata: metadata
                )
                currentEntryID = entryID
                entryStartTime = Date()
                logService?.log(
                    "\(prefix) Created entry for \(resolution.ticketID)"
                )
            } catch {
                logService?.log(
                    "\(prefix) Failed to create entry: \(error)",
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
        let detectedFrom: String
    }

    private func resolveTicket(
        tabInfo: BrowserTabInfo
    ) async -> TicketResolution? {
        if let url = tabInfo.url,
           let ticket = BrowserTabService.extractJiraTicketFromURL(url) {
            return TicketResolution(ticketID: ticket, detectedFrom: "jira")
        }

        if let url = tabInfo.url,
           let prRef = BrowserTabService.parseBitbucketPRURL(url) {
            let detail = await fetchOrCachePR(ref: prRef)
            if let detail {
                logService?.log(
                    "[\(config.displayName)] Bitbucket PR: "
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
                let context = ModelContext(self.modelContainer)
                if let entry = context.model(for: entryID) as? TimeEntry {
                    context.delete(entry)
                    try? context.save()
                }
            }
        } else {
            let service = TimeEntryService(modelContainer: modelContainer)
            Task {
                try? await service.finalize(
                    entryID: entryID, endTime: Date()
                )
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
        let predicate = #Predicate<IntegrationConfig> {
            $0.type == bbType
        }
        let descriptor = FetchDescriptor<IntegrationConfig>(
            predicate: predicate
        )

        if let config = try? context.fetch(descriptor).first,
           config.isEnabled {
            bbToken = try? KeychainService.retrieve(
                key: "bitbucket_token"
            )
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
