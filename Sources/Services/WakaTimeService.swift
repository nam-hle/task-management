import Foundation

// MARK: - Models

struct BranchSegment: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct BranchActivity: Identifiable {
    let id: String
    let project: String
    let branch: String
    let segments: [BranchSegment]
    let totalDuration: TimeInterval
}

enum WakaTimeError: Error, LocalizedError {
    case noAPIKey
    case networkError(Error)
    case httpError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            "WakaTime API key not found in ~/.wakatime.cfg"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .httpError(let code):
            "HTTP error \(code)"
        case .decodingError(let error):
            "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - WakaTime API Response Models

private struct WakaTimeDurationsResponse: Codable {
    let data: [WakaTimeDuration]
}

private struct WakaTimeDuration: Codable {
    let project: String?
    let branch: String?
    let time: Double
    let duration: Double
}

private struct WakaTimeHeartbeatsResponse: Codable {
    let data: [WakaTimeHeartbeat]
}

private struct WakaTimeHeartbeat: Codable {
    let project: String?
    let branch: String?
    let time: Double
}

// MARK: - Service

@MainActor @Observable
final class WakaTimeService {
    var isConfigured = false
    var isLoading = false
    var error: WakaTimeError?
    var branches: [BranchActivity] = []

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.isConfigured = WakaTimeConfigReader.readAPIKey() != nil
    }

    func fetchBranches(for date: Date) async {
        guard let apiKey = WakaTimeConfigReader.readAPIKey() else {
            self.isConfigured = false
            self.error = .noAPIKey
            return
        }

        isConfigured = true
        isLoading = true
        error = nil

        defer { isLoading = false }

        let dateString = Self.dateFormatter.string(from: date)
        let credentials = Data("\(apiKey):".utf8).base64EncodedString()

        // Fetch durations (accurate times) and heartbeats (branch info) in parallel
        async let durationsResult = fetchJSON(
            path: "durations?date=\(dateString)",
            credentials: credentials,
            as: WakaTimeDurationsResponse.self
        )
        async let heartbeatsResult = fetchJSON(
            path: "heartbeats?date=\(dateString)",
            credentials: credentials,
            as: WakaTimeHeartbeatsResponse.self
        )

        do {
            let durations = try await durationsResult
            let heartbeats = try await heartbeatsResult
            self.branches = Self.aggregate(
                durations: durations.data, heartbeats: heartbeats.data
            )
        } catch let err as WakaTimeError {
            self.error = err
        } catch let decodingError as DecodingError {
            self.error = .decodingError(decodingError)
        } catch {
            self.error = .networkError(error)
        }
    }

    private func fetchJSON<T: Decodable>(
        path: String, credentials: String, as type: T.Type
    ) async throws -> T {
        guard let url = URL(
            string: "https://wakatime.com/api/v1/users/current/\(path)"
        ) else {
            throw WakaTimeError.networkError(
                URLError(.badURL)
            )
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Basic \(credentials)", forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WakaTimeError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Aggregation

    private static func aggregate(
        durations: [WakaTimeDuration], heartbeats: [WakaTimeHeartbeat]
    ) -> [BranchActivity] {
        // Build a sorted list of heartbeats for branch lookups
        let sortedHeartbeats = heartbeats
            .filter { $0.branch != nil }
            .sorted { $0.time < $1.time }

        // Annotate each duration segment with a branch from the nearest heartbeat
        struct AnnotatedDuration {
            let project: String
            let branch: String
            let time: Double
            let duration: Double
        }

        let annotated: [AnnotatedDuration] = durations.map { dur in
            let project = dur.project ?? "Unknown"

            // If the durations API already has branch info, use it
            if let branch = dur.branch, !branch.isEmpty {
                return AnnotatedDuration(
                    project: project, branch: branch,
                    time: dur.time, duration: dur.duration
                )
            }

            // Find the nearest heartbeat within this duration's time range
            let segStart = dur.time
            let segEnd = dur.time + dur.duration
            let branch = findBranch(
                in: sortedHeartbeats, project: project,
                from: segStart, to: segEnd
            )

            return AnnotatedDuration(
                project: project, branch: branch,
                time: dur.time, duration: dur.duration
            )
        }

        // Group by (project, branch)
        var grouped: [String: [AnnotatedDuration]] = [:]
        for item in annotated {
            let key = "\(item.project)\0\(item.branch)"
            grouped[key, default: []].append(item)
        }

        return grouped.compactMap { key, items -> BranchActivity? in
            let parts = key.split(separator: "\0", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let project = String(parts[0])
            let branch = String(parts[1])

            let segments = items.map { item in
                let start = Date(timeIntervalSince1970: item.time)
                let end = Date(timeIntervalSince1970: item.time + item.duration)
                return BranchSegment(start: start, end: end)
            }

            let totalDuration = items.reduce(0.0) { $0 + $1.duration }

            return BranchActivity(
                id: key,
                project: project,
                branch: branch,
                segments: segments,
                totalDuration: totalDuration
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    /// Find the branch from the nearest heartbeat that falls within a time range.
    private static func findBranch(
        in heartbeats: [WakaTimeHeartbeat],
        project: String, from start: Double, to end: Double
    ) -> String {
        // First try: heartbeat within the segment's time range matching project
        for hb in heartbeats {
            if hb.time >= start, hb.time <= end,
               hb.project == project, let branch = hb.branch {
                return branch
            }
        }

        // Fallback: nearest heartbeat for this project (within 5 min tolerance)
        let tolerance: Double = 300
        var bestBranch: String?
        var bestDistance = Double.infinity
        let midpoint = (start + end) / 2.0

        for hb in heartbeats where hb.project == project {
            let distance = abs(hb.time - midpoint)
            if distance < tolerance, distance < bestDistance {
                bestDistance = distance
                bestBranch = hb.branch
            }
        }

        return bestBranch ?? "default"
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
