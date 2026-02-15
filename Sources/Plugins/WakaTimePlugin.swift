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
    private let wakaTimeService = WakaTimeService()
    private var syncTimer: Timer?
    private var syncInterval: TimeInterval = 300 // 5 minutes

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
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

    // MARK: - Data Sync

    func fetchAndSync(for date: Date) async {
        isLoading = true
        defer { isLoading = false }

        await wakaTimeService.fetchBranches(for: date)

        if let error = wakaTimeService.error {
            lastError = error.localizedDescription
            status = .error(lastError!)
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

        for branch in branches {
            if excludedProjects.contains(branch.project) { continue }

            // Resolve ticket ID
            let ticketID = TicketInferenceService.resolveTicketID(
                branch: branch.branch,
                pageTitle: nil,
                pageURL: nil,
                appName: nil,
                overrides: overrides
            )

            let metadata = "{\"project\":\"\(escapeJSON(branch.project))\",\"branch\":\"\(escapeJSON(branch.branch))\"}"

            for segment in branch.segments {
                do {
                    // Check for existing entry overlap to avoid duplicates
                    let existingEntries = try await service.entries(for: segment.start)
                    let wakatimeSource = "wakatime"
                    let hasOverlap = existingEntries.contains { entry in
                        entry.sourcePluginID == wakatimeSource
                            && entry.startTime <= segment.end
                            && (entry.endTime ?? Date()) >= segment.start
                    }

                    if !hasOverlap {
                        _ = try await service.createFinalized(
                            startTime: segment.start,
                            endTime: segment.end,
                            source: .wakatime,
                            applicationName: branch.project,
                            sourcePluginID: "wakatime",
                            ticketID: ticketID,
                            contextMetadata: metadata
                        )
                    }
                } catch {
                    print("WakaTime: Failed to create entry for segment: \(error)")
                }
            }
        }

        if status != .inactive {
            status = .active
            lastError = nil
        }
    }

    // MARK: - Helpers

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
