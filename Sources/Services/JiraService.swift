import Foundation
import SwiftData

struct JiraTicketInfo: Identifiable {
    var id: String { ticketID }
    let ticketID: String
    let summary: String
    let status: String
    let statusCategoryKey: String
    let assignee: String?
    let priority: String?
    let issueType: String?
    let projectKey: String?
    let projectName: String?
    let browseURL: URL?
    let fetchedAt: Date
}

@MainActor @Observable
final class JiraService: JiraServiceProtocol {
    private var cache: [String: JiraTicketInfo] = [:]
    private var inFlight: [String: Task<JiraTicketInfo?, Never>] = [:]
    private var cacheTTL: TimeInterval { AppConfig.jiraCacheTTL }
    private(set) var projectNames: [String: String] = [:]

    private let modelContainer: ModelContainer
    private let logService: LogService?

    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        self.modelContainer = modelContainer
        self.logService = logService
    }

    func ticketInfo(for ticketID: String) async -> JiraTicketInfo? {
        if let cached = cache[ticketID],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            logService?.log("Cache hit for \(ticketID)")
            return cached
        }

        if let existing = inFlight[ticketID] {
            return await existing.value
        }

        let task = Task<JiraTicketInfo?, Never> { [weak self] in
            guard let self else { return nil }
            let info = await self.fetchFromJira(ticketID: ticketID)
            if let info {
                self.cache[ticketID] = info
                self.cacheProjectName(from: info)
            }
            self.inFlight.removeValue(forKey: ticketID)
            return info
        }

        inFlight[ticketID] = task
        return await task.value
    }

    func prefetch(ticketID: String) {
        if let cached = cache[ticketID],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return
        }
        guard inFlight[ticketID] == nil else { return }

        let task = Task<JiraTicketInfo?, Never> { [weak self] in
            guard let self else { return nil }
            let info = await self.fetchFromJira(ticketID: ticketID)
            if let info {
                self.cache[ticketID] = info
                self.cacheProjectName(from: info)
            }
            self.inFlight.removeValue(forKey: ticketID)
            return info
        }
        inFlight[ticketID] = task
    }

    func projectName(for projectKey: String) -> String? {
        projectNames[projectKey]
    }

    // MARK: - Private

    private func cacheProjectName(from info: JiraTicketInfo) {
        if let key = info.projectKey, let name = info.projectName {
            projectNames[key] = name
        }
    }

    private func fetchFromJira(ticketID: String) async -> JiraTicketInfo? {
        guard let credentials = loadCredentials() else {
            logService?.log("No credentials found for \(ticketID)", level: .error)
            return nil
        }

        let baseURL = credentials.serverURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fields = "summary,status,assignee,priority,issuetype,project"
        let urlString = "\(baseURL)/rest/api/2/issue/\(ticketID)?fields=\(fields)"
        logService?.log("Fetching \(urlString)")

        guard let url = URL(string: urlString) else {
            logService?.log("Invalid URL: \(urlString)", level: .error)
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logService?.log("No HTTP response", level: .error)
                return nil
            }
            logService?.log("HTTP \(httpResponse.statusCode) for \(ticketID)")
            guard httpResponse.statusCode == 200 else {
                if let body = String(data: data, encoding: .utf8) {
                    logService?.log(
                        "Response body: \(String(body.prefix(300)))",
                        level: .error
                    )
                }
                return nil
            }
            return parseResponse(data: data, ticketID: ticketID, baseURL: baseURL)
        } catch {
            logService?.log("Error: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    private struct JiraCredentials {
        let serverURL: String
        let token: String
    }

    @MainActor
    private func loadCredentials() -> JiraCredentials? {
        let context = ModelContext(modelContainer)

        // Fetch all configs to debug
        let allDescriptor = FetchDescriptor<IntegrationConfig>()
        let allConfigs: [IntegrationConfig]
        do {
            allConfigs = try context.fetch(allDescriptor)
        } catch {
            logService?.log(
                "Failed to fetch configs: \(error)", level: .error
            )
            return nil
        }
        logService?.log("All configs: \(allConfigs.map { "type=\($0.type.rawValue) url=\($0.serverURL) enabled=\($0.isEnabled)" })")

        let token = try? KeychainService.retrieve(key: "jira_token")
        logService?.log("Keychain token present: \(token != nil && !token!.isEmpty)")

        guard let config = allConfigs.first(where: { $0.type == .jira && $0.isEnabled }),
              !config.serverURL.isEmpty,
              let token, !token.isEmpty else {
            logService?.log("Credential check failed", level: .error)
            return nil
        }
        return JiraCredentials(
            serverURL: config.serverURL,
            token: token
        )
    }

    private func parseResponse(data: Data, ticketID: String, baseURL: String) -> JiraTicketInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any],
              let summary = fields["summary"] as? String else {
            logService?.log("Failed to parse response for \(ticketID)", level: .error)
            return nil
        }

        let status: String
        let statusCategoryKey: String
        if let statusObj = fields["status"] as? [String: Any] {
            status = statusObj["name"] as? String ?? "Unknown"
            let category = statusObj["statusCategory"] as? [String: Any]
            statusCategoryKey = category?["key"] as? String ?? "undefined"
        } else {
            status = "Unknown"
            statusCategoryKey = "undefined"
        }

        let assignee: String?
        if let assigneeObj = fields["assignee"] as? [String: Any] {
            assignee = assigneeObj["displayName"] as? String
        } else {
            assignee = nil
        }

        let priority: String?
        if let priorityObj = fields["priority"] as? [String: Any] {
            priority = priorityObj["name"] as? String
        } else {
            priority = nil
        }

        let issueType: String?
        if let typeObj = fields["issuetype"] as? [String: Any] {
            issueType = typeObj["name"] as? String
        } else {
            issueType = nil
        }

        let projectKey: String?
        let projectName: String?
        if let projectObj = fields["project"] as? [String: Any] {
            projectKey = projectObj["key"] as? String
            projectName = projectObj["name"] as? String
        } else {
            projectKey = nil
            projectName = nil
        }

        let browseURL = URL(string: "\(baseURL)/browse/\(ticketID)")

        let info = JiraTicketInfo(
            ticketID: ticketID,
            summary: summary,
            status: status,
            statusCategoryKey: statusCategoryKey,
            assignee: assignee,
            priority: priority,
            issueType: issueType,
            projectKey: projectKey,
            projectName: projectName,
            browseURL: browseURL,
            fetchedAt: Date()
        )
        logService?.log(
            "Parsed \(ticketID): " +
            "[\(issueType ?? "?")] \"\(summary)\" " +
            "status=\(status) assignee=\(assignee ?? "none") " +
            "priority=\(priority ?? "none")"
        )
        return info
    }
}
