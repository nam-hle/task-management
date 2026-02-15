import SwiftUI
import SwiftData

struct IntegrationSettingsView: View {
    @Query
    private var configs: [IntegrationConfig]
    @Environment(\.modelContext) private var modelContext

    @State private var jiraURL = ""
    @State private var jiraToken = ""
    @State private var bitbucketURL = ""
    @State private var bitbucketToken = ""

    @State private var jiraStatus: ConnectionStatus?
    @State private var bbStatus: ConnectionStatus?

    @State private var jiraSaveTask: Task<Void, Never>?
    @State private var bbSaveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Jira") {
                TextField("Server URL", text: $jiraURL)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Base URL before /browse"
                    + " — e.g. https://jira.company.com/jira"
                )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                SecureField("Personal Access Token", text: $jiraToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") {
                        testJiraConnection()
                    }
                    .controlSize(.small)
                    .disabled(
                        jiraURL.isEmpty || jiraToken.isEmpty
                        || jiraStatus == .testing
                    )

                    if jiraStatus == .testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                statusRow(jiraStatus)
            }
            .onChange(of: jiraURL) { debouncedSaveJira() }
            .onChange(of: jiraToken) { debouncedSaveJira() }

            Section("Bitbucket") {
                TextField("Server URL", text: $bitbucketURL)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. https://bitbucket.company.com")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                SecureField("Personal Access Token", text: $bitbucketToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") {
                        testBitbucketConnection()
                    }
                    .controlSize(.small)
                    .disabled(
                        bitbucketURL.isEmpty || bitbucketToken.isEmpty
                        || bbStatus == .testing
                    )

                    if bbStatus == .testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                statusRow(bbStatus)
            }
            .onChange(of: bitbucketURL) { debouncedSaveBitbucket() }
            .onChange(of: bitbucketToken) { debouncedSaveBitbucket() }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    @ViewBuilder
    private func statusRow(_ status: ConnectionStatus?) -> some View {
        if let status {
            switch status {
            case .connected(let message):
                Label(message, systemImage: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .error(let message):
                Label(message, systemImage: "circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            case .testing:
                EmptyView()
            }
        }
    }

    // MARK: - Load & Save

    private func loadSettings() {
        let jiraConfig = configs.first { $0.type == .jira }
        jiraURL = jiraConfig?.serverURL ?? ""
        jiraToken = KeychainService.retrieve(key: "jira_token") ?? ""

        let bbConfig = configs.first { $0.type == .bitbucket }
        bitbucketURL = bbConfig?.serverURL ?? ""
        bitbucketToken =
            KeychainService.retrieve(key: "bitbucket_token") ?? ""

        if !jiraURL.isEmpty && !jiraToken.isEmpty {
            testJiraConnection()
        }
        if !bitbucketURL.isEmpty && !bitbucketToken.isEmpty {
            testBitbucketConnection()
        }
    }

    private func debouncedSaveJira() {
        jiraSaveTask?.cancel()
        jiraSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveConfig(type: .jira, url: jiraURL, username: "")
            if !jiraToken.isEmpty {
                try? KeychainService.store(
                    key: "jira_token", value: jiraToken
                )
            }
        }
    }

    private func debouncedSaveBitbucket() {
        bbSaveTask?.cancel()
        bbSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveConfig(
                type: .bitbucket, url: bitbucketURL, username: ""
            )
            if !bitbucketToken.isEmpty {
                try? KeychainService.store(
                    key: "bitbucket_token", value: bitbucketToken
                )
            }
        }
    }

    // MARK: - Test Connections

    private func testJiraConnection() {
        jiraStatus = .testing

        let baseURL = jiraURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/rest/api/2/myself")
        else {
            jiraStatus = .error("Invalid server URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "application/json", forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Bearer \(jiraToken)",
            forHTTPHeaderField: "Authorization"
        )

        Task {
            do {
                let (data, response) =
                    try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    jiraStatus = .error("No response from server")
                    return
                }

                if http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(
                        with: data
                    ) as? [String: Any],
                       let name = json["displayName"] as? String
                    {
                        jiraStatus = .connected(
                            "Connected as \(name)"
                        )
                    } else {
                        jiraStatus = .error(
                            "Got 200 but unexpected response"
                            + " — check the base URL includes"
                            + " the context path (e.g. /jira)"
                        )
                    }
                } else if http.statusCode == 401 {
                    jiraStatus = .error(
                        "Authentication failed — check your token"
                    )
                } else if http.statusCode == 403 {
                    jiraStatus = .error(
                        "Forbidden — token lacks permissions"
                    )
                } else {
                    jiraStatus = .error(
                        "HTTP \(http.statusCode) — check server URL"
                    )
                }
            } catch {
                jiraStatus = .error(
                    "Connection failed:"
                    + " \(error.localizedDescription)"
                )
            }
        }
    }

    private func testBitbucketConnection() {
        bbStatus = .testing

        let baseURL = bitbucketURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseURL)/rest/api/1.0/users"

        guard let url = URL(string: urlString) else {
            bbStatus = .error("Invalid server URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "application/json", forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Bearer \(bitbucketToken)",
            forHTTPHeaderField: "Authorization"
        )

        Task {
            do {
                let (_, response) =
                    try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    bbStatus = .error("No response from server")
                    return
                }

                if http.statusCode == 200 {
                    bbStatus = .connected(
                        "Connected to Bitbucket Server"
                    )
                } else if http.statusCode == 401 {
                    bbStatus = .error(
                        "Authentication failed — check your token"
                    )
                } else if http.statusCode == 403 {
                    bbStatus = .error(
                        "Forbidden — token lacks permissions"
                    )
                } else {
                    bbStatus = .error(
                        "HTTP \(http.statusCode) — check server URL"
                    )
                }
            } catch {
                bbStatus = .error(
                    "Connection failed:"
                    + " \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Persistence

    private func saveConfig(
        type: IntegrationType, url: String, username: String
    ) {
        if let existing = configs.first(where: { $0.type == type }) {
            existing.serverURL = url
            existing.username = username
        } else {
            let config = IntegrationConfig(
                type: type,
                serverURL: url,
                username: username
            )
            modelContext.insert(config)
        }
        try? modelContext.save()
    }
}

private enum ConnectionStatus: Equatable {
    case connected(String)
    case error(String)
    case testing
}
