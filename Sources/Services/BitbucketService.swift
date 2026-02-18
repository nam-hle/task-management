import Foundation
import SwiftData

struct BitbucketPRInfo: Identifiable {
    var id: String { prURL }
    let prURL: String
    let prNumber: Int
    let repoSlug: String
    let projectKey: String
    let title: String
    let status: String
    let author: String
    let reviewers: [String]
    let sourceBranch: String
    let ticketID: String?
    let browseURL: URL?
    let fetchedAt: Date
}

@MainActor @Observable
final class BitbucketService {
    private var cache: [String: BitbucketPRInfo] = [:]
    private var inFlight: [String: Task<BitbucketPRInfo?, Never>] = [:]
    private let cacheTTL: TimeInterval = 86_400

    private let modelContainer: ModelContainer
    private let logService: LogService?

    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        self.modelContainer = modelContainer
        self.logService = logService
    }

    func prInfo(for prURL: String) async -> BitbucketPRInfo? {
        if let cached = cache[prURL],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            logService?.log("BB cache hit for \(prURL)")
            return cached
        }

        if let existing = inFlight[prURL] {
            return await existing.value
        }

        let task = Task<BitbucketPRInfo?, Never> { [weak self] in
            guard let self else { return nil }
            let info = await self.fetchPR(prURL: prURL)
            if let info {
                self.cache[prURL] = info
            }
            self.inFlight.removeValue(forKey: prURL)
            return info
        }

        inFlight[prURL] = task
        return await task.value
    }

    func prefetch(prURL: String) {
        if let cached = cache[prURL],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return
        }
        guard inFlight[prURL] == nil else { return }

        let task = Task<BitbucketPRInfo?, Never> { [weak self] in
            guard let self else { return nil }
            let info = await self.fetchPR(prURL: prURL)
            if let info {
                self.cache[prURL] = info
            }
            self.inFlight.removeValue(forKey: prURL)
            return info
        }
        inFlight[prURL] = task
    }

    // MARK: - Private

    private struct BitbucketCredentials {
        let serverURL: String
        let token: String
    }

    @MainActor
    private func loadCredentials() -> BitbucketCredentials? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<IntegrationConfig>()
        let configs: [IntegrationConfig]
        do {
            configs = try context.fetch(descriptor)
        } catch {
            logService?.log(
                "Failed to fetch BB configs: \(error)", level: .error
            )
            return nil
        }

        let token = try? KeychainService.retrieve(key: "bitbucket_token")
        logService?.log(
            "BB keychain token present: \(token != nil && !token!.isEmpty)"
        )

        guard let config = configs.first(
            where: { $0.type == .bitbucket && $0.isEnabled }
        ),
              !config.serverURL.isEmpty,
              let token, !token.isEmpty else {
            logService?.log("BB credential check failed", level: .error)
            return nil
        }

        return BitbucketCredentials(
            serverURL: config.serverURL,
            token: token
        )
    }

    private func fetchPR(prURL: String) async -> BitbucketPRInfo? {
        guard let ref = BrowserTabService.parseBitbucketPRURL(prURL) else {
            logService?.log(
                "Cannot parse BB PR URL: \(prURL)", level: .error
            )
            return nil
        }

        guard let credentials = loadCredentials() else {
            logService?.log(
                "No BB credentials for \(prURL)", level: .error
            )
            return nil
        }

        let base = credentials.serverURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiURL = "\(base)/rest/api/1.0/projects/\(ref.projectKey)"
            + "/repos/\(ref.repoSlug)"
            + "/pull-requests/\(ref.prNumber)"

        logService?.log("Fetching \(apiURL)")

        guard let url = URL(string: apiURL) else {
            logService?.log("Invalid API URL: \(apiURL)", level: .error)
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        request.setValue(
            "Bearer \(credentials.token)",
            forHTTPHeaderField: "Authorization"
        )

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )
            guard let http = response as? HTTPURLResponse else {
                logService?.log("No HTTP response", level: .error)
                return nil
            }
            logService?.log("HTTP \(http.statusCode) for \(prURL)")
            guard http.statusCode == 200 else {
                if let body = String(data: data, encoding: .utf8) {
                    logService?.log(
                        "Response body: \(String(body.prefix(300)))",
                        level: .error
                    )
                }
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                logService?.log(
                    "Failed to parse JSON for \(prURL)", level: .error
                )
                return nil
            }

            return parseResponse(
                json: json, prURL: prURL, ref: ref
            )
        } catch {
            logService?.log(
                "BB fetch error: \(error.localizedDescription)",
                level: .error
            )
            return nil
        }
    }

    private func parseResponse(
        json: [String: Any],
        prURL: String,
        ref: BitbucketPRRef
    ) -> BitbucketPRInfo {
        let title = json["title"] as? String ?? ""
        let state = json["state"] as? String ?? "UNKNOWN"

        let authorObj = json["author"] as? [String: Any]
        let authorUser = authorObj?["user"] as? [String: Any]
        let author = authorUser?["displayName"] as? String ?? "Unknown"

        let fromRef = json["fromRef"] as? [String: Any]
        let sourceBranch = fromRef?["displayId"] as? String ?? ""

        let reviewersList = json["reviewers"] as? [[String: Any]] ?? []
        let reviewers = reviewersList.compactMap { reviewer -> String? in
            let user = reviewer["user"] as? [String: Any]
            return user?["displayName"] as? String
        }

        let titleTicket = BrowserTabService.extractTicketID(from: title)
        let branchTicket = BrowserTabService.extractTicketID(from: sourceBranch)
        let ticketID = titleTicket ?? branchTicket

        logService?.log(
            "BB ticket resolve: title=\"\(title)\" → \(titleTicket ?? "none"), "
            + "branch=\"\(sourceBranch)\" → \(branchTicket ?? "none"), "
            + "resolved=\(ticketID ?? "none")"
        )

        let info = BitbucketPRInfo(
            prURL: prURL,
            prNumber: ref.prNumber,
            repoSlug: ref.repoSlug,
            projectKey: ref.projectKey,
            title: title,
            status: state,
            author: author,
            reviewers: reviewers,
            sourceBranch: sourceBranch,
            ticketID: ticketID,
            browseURL: URL(string: prURL),
            fetchedAt: Date()
        )
        logService?.log(
            "Parsed BB PR #\(ref.prNumber): \"\(title)\" "
            + "status=\(state) author=\(author) "
            + "branch=\(sourceBranch) reviewers=\(reviewers.count)"
        )
        return info
    }
}
