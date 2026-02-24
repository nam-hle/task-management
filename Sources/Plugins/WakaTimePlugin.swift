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
    private var syncInterval: TimeInterval { AppConfig.wakatimeSyncInterval }

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

        // Resolve tickets and aggregate by ticketID
        struct TicketAccumulator {
            var totalDuration: TimeInterval = 0
            var earliestStart: Date = .distantFuture
            var latestEnd: Date = .distantPast
            var branches: [(project: String, branch: String, duration: TimeInterval)] = []
        }

        var ticketAccumulators: [String: TicketAccumulator] = [:]

        for branch in branches {
            if excludedProjects.contains(branch.project) {
                logService?.log(
                    "WakaTime: skip excluded project \(branch.project)"
                )
                continue
            }

            let ticketID = TicketInferenceService.resolveTicketID(
                branch: branch.branch,
                pageTitle: nil,
                pageURL: nil,
                appName: nil,
                overrides: overrides
            ) ?? "unassigned"

            let durationMin = String(
                format: "%.1f", branch.totalDuration / 60
            )
            logService?.log(
                "WakaTime: \(branch.project)/\(branch.branch)"
                + " → \(ticketID)"
                + " (\(durationMin)m, \(branch.segments.count) segments)"
            )

            var acc = ticketAccumulators[ticketID] ?? TicketAccumulator()
            acc.totalDuration += branch.totalDuration
            acc.branches.append((
                project: branch.project,
                branch: branch.branch,
                duration: branch.totalDuration
            ))
            for segment in branch.segments {
                if segment.start < acc.earliestStart {
                    acc.earliestStart = segment.start
                }
                if segment.end > acc.latestEnd {
                    acc.latestEnd = segment.end
                }
            }
            ticketAccumulators[ticketID] = acc
        }

        // Create or update one entry per ticket
        var createdCount = 0
        var updatedCount = 0

        for (ticketKey, acc) in ticketAccumulators {
            let resolvedTicketID: String? = ticketKey == "unassigned"
                ? nil : ticketKey

            let branchesJSON = acc.branches.map {
                "{\"project\":\"\(escapeJSON($0.project))\","
                + "\"branch\":\"\(escapeJSON($0.branch))\","
                + "\"duration\":\($0.duration)}"
            }.joined(separator: ",")
            let metadata = "{\"branches\":[\(branchesJSON)]}"

            do {
                let (_, isNew) = try await service.upsertWakaTimeEntry(
                    ticketID: resolvedTicketID,
                    date: acc.earliestStart,
                    startTime: acc.earliestStart,
                    endTime: acc.latestEnd,
                    duration: acc.totalDuration,
                    applicationName: acc.branches.first?.project,
                    contextMetadata: metadata
                )

                if isNew {
                    createdCount += 1
                } else {
                    updatedCount += 1
                }
                logService?.log(
                    "WakaTime: \(isNew ? "+" : "~") \(ticketKey)"
                    + " \(df.string(from: acc.earliestStart))"
                    + "–\(df.string(from: acc.latestEnd))"
                    + " \(String(format: "%.1f", acc.totalDuration / 60))m"
                )
            } catch {
                logService?.log(
                    "WakaTime: failed to store \(ticketKey) — \(error)",
                    level: .error
                )
            }
        }

        logService?.log(
            "WakaTime: sync done — \(createdCount) created,"
            + " \(updatedCount) updated"
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
