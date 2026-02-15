import Foundation
import SwiftData

@MainActor
@Observable
final class WakaTimePlugin: TimeTrackingPlugin {
    let id = "wakatime"
    let displayName = "WakaTime"
    private(set) var status: PluginStatus = .inactive
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let modelContainer: ModelContainer
    private let logService: LogService?
    private let wakaTimeService = WakaTimeService()
    private var syncTimer: Timer?
    private var syncInterval: TimeInterval = 300 // 5 minutes

    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        self.modelContainer = modelContainer
        self.logService = logService
    }

    // MARK: - TimeTrackingPlugin

    nonisolated func isAvailable() -> Bool {
        WakaTimeConfigReader.readAPIKey() != nil
    }

    func start() async throws {
        guard WakaTimeConfigReader.readAPIKey() != nil else {
            status = .unavailable
            return
        }

        status = .active
        lastError = nil

        // Initial fetch
        await fetchAndSync(for: Date())

        // Start periodic sync
        syncTimer = Timer.scheduledTimer(
            withTimeInterval: syncInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAndSync(for: Date())
            }
        }
    }

    func stop() async throws {
        syncTimer?.invalidate()
        syncTimer = nil
        status = .inactive
    }

    func sync() async {
        guard status == .active else { return }
        await fetchAndSync(for: Date())
    }

    // MARK: - Data Sync

    func fetchAndSync(for date: Date) async {
        isLoading = true
        defer { isLoading = false }

        let df = Self.timeFormatter
        logService?.log("WakaTime: fetching data for \(Self.dateFormatter.string(from: date))")

        await wakaTimeService.fetchBranches(for: date)

        if let error = wakaTimeService.error {
            lastError = error.localizedDescription
            status = .error(lastError!)
            logService?.log("WakaTime: fetch failed — \(lastError!)", level: .error)
            return
        }

        // Load overrides and settings for ticket inference
        let context = ModelContext(modelContainer)
        let overrides = (try? context.fetch(FetchDescriptor<TicketOverride>())) ?? []
        let excludedData = UserDefaults.standard.data(forKey: "excludedProjectsData")
        let excludedProjects: Set<String> = excludedData
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []

        let branches = wakaTimeService.branches
        let service = TimeEntryService(modelContainer: modelContainer)

        logService?.log(
            "WakaTime: received \(branches.count) branches"
        )

        var createdCount = 0
        var updatedCount = 0
        var skippedCount = 0

        for branch in branches {
            if excludedProjects.contains(branch.project) {
                logService?.log(
                    "WakaTime: skip excluded project \(branch.project)"
                )
                continue
            }

            // Resolve ticket ID
            let ticketID = TicketInferenceService.resolveTicketID(
                branch: branch.branch,
                pageTitle: nil,
                pageURL: nil,
                appName: nil,
                overrides: overrides
            )

            let durationMin = String(
                format: "%.1f", branch.totalDuration / 60
            )
            logService?.log(
                "WakaTime: \(branch.project)/\(branch.branch)"
                + " → \(ticketID ?? "unassigned")"
                + " (\(durationMin)m, \(branch.segments.count) segments)"
            )

            let metadata = "{\"project\":\"\(escapeJSON(branch.project))\",\"branch\":\"\(escapeJSON(branch.branch))\"}"

            for segment in branch.segments {
                do {
                    // Check for existing entry overlap to avoid duplicates
                    let existingEntries = try await service.entries(for: segment.start)
                    let wakatimeSource = "wakatime"
                    let overlapping = existingEntries.first { entry in
                        entry.sourcePluginID == wakatimeSource
                            && entry.startTime <= segment.end
                            && (entry.endTime ?? Date()) >= segment.start
                    }

                    if let existing = overlapping {
                        if existing.ticketID == nil, let ticketID {
                            try await service.assignTicket(
                                entryIDs: [existing.persistentModelID],
                                ticketID: ticketID
                            )
                            updatedCount += 1
                            logService?.log(
                                "WakaTime:   ~ update"
                                + " \(df.string(from: existing.startTime))"
                                + "–\(df.string(from: existing.endTime ?? Date()))"
                                + " → \(ticketID)"
                            )
                        } else {
                            skippedCount += 1
                            logService?.log(
                                "WakaTime:   ~ skip"
                                + " \(df.string(from: segment.start))"
                                + "–\(df.string(from: segment.end))"
                                + " (overlaps existing"
                                + " \(df.string(from: existing.startTime))"
                                + "–\(df.string(from: existing.endTime ?? Date()))"
                                + " ticket=\(existing.ticketID ?? "nil"))"
                            )
                        }
                    } else {
                        _ = try await service.createFinalized(
                            startTime: segment.start,
                            endTime: segment.end,
                            source: .wakatime,
                            applicationName: branch.project,
                            sourcePluginID: "wakatime",
                            ticketID: ticketID,
                            contextMetadata: metadata
                        )
                        createdCount += 1
                        logService?.log(
                            "WakaTime:   + entry"
                            + " \(df.string(from: segment.start))"
                            + "–\(df.string(from: segment.end))"
                        )
                    }
                } catch {
                    logService?.log(
                        "WakaTime: failed to create entry — \(error)",
                        level: .error
                    )
                }
            }
        }

        logService?.log(
            "WakaTime: sync done — \(createdCount) created,"
            + " \(updatedCount) updated,"
            + " \(skippedCount) skipped"
        )

        if status != .inactive {
            status = .active
            lastError = nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Helpers

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
