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
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var isBBTesting = false

    var body: some View {
        Form {
            Section("Jira") {
                TextField("Server URL", text: $jiraURL)
                    .textFieldStyle(.roundedBorder)
                Text("Base URL before /browse — e.g. https://jira.company.com/jira")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                SecureField("Personal Access Token", text: $jiraToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Jira Settings") {
                        saveJiraSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Test Connection") {
                        testJiraConnection()
                    }
                    .controlSize(.small)
                    .disabled(jiraURL.isEmpty || jiraToken.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Bitbucket") {
                TextField("Server URL", text: $bitbucketURL)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. https://bitbucket.company.com")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                SecureField("Personal Access Token", text: $bitbucketToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Bitbucket Settings") {
                        saveBitbucketSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Test Connection") {
                        testBitbucketConnection()
                    }
                    .controlSize(.small)
                    .disabled(
                        bitbucketURL.isEmpty
                        || bitbucketToken.isEmpty
                        || isBBTesting
                    )

                    if isBBTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("WakaTime") {
                let hasKey = WakaTimeConfigReader.readAPIKey() != nil
                LabeledContent("Status") {
                    if hasKey {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not configured", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("WakaTime reads its API key from ~/.wakatime.cfg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = statusMessage {
                Section {
                    Text(message)
                        .foregroundStyle(statusIsError ? .red : .green)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        let jiraConfig = configs.first { $0.type == .jira }
        jiraURL = jiraConfig?.serverURL ?? ""
        jiraToken = KeychainService.retrieve(key: "jira_token") ?? ""

        let bbConfig = configs.first { $0.type == .bitbucket }
        bitbucketURL = bbConfig?.serverURL ?? ""
        bitbucketToken = KeychainService.retrieve(key: "bitbucket_token") ?? ""
    }

    private func saveJiraSettings() {
        saveConfig(type: .jira, url: jiraURL, username: "")
        if !jiraToken.isEmpty {
            try? KeychainService.store(key: "jira_token", value: jiraToken)
        }
        statusIsError = false
        statusMessage = "Jira settings saved"
    }

    private func testJiraConnection() {
        isTesting = true
        statusMessage = nil

        let baseURL = jiraURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/rest/api/2/myself") else {
            statusIsError = true
            statusMessage = "Invalid server URL"
            isTesting = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jiraToken)", forHTTPHeaderField: "Authorization")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    statusIsError = true
                    statusMessage = "No response from server"
                    isTesting = false
                    return
                }

                if http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                       let displayName = json["displayName"] as? String {
                        statusIsError = false
                        statusMessage = "Connected as \(displayName)"
                    } else {
                        statusIsError = true
                        statusMessage = "Got 200 but unexpected response — check the base URL includes the context path (e.g. /jira)"
                    }
                } else if http.statusCode == 401 {
                    statusIsError = true
                    statusMessage = "Authentication failed — check your token"
                } else if http.statusCode == 403 {
                    statusIsError = true
                    statusMessage = "Forbidden — token lacks permissions"
                } else {
                    statusIsError = true
                    statusMessage = "HTTP \(http.statusCode) — check server URL"
                }
            } catch {
                statusIsError = true
                statusMessage = "Connection failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func saveBitbucketSettings() {
        saveConfig(
            type: .bitbucket,
            url: bitbucketURL,
            username: ""
        )
        if !bitbucketToken.isEmpty {
            try? KeychainService.store(
                key: "bitbucket_token", value: bitbucketToken
            )
        }
        statusIsError = false
        statusMessage = "Bitbucket settings saved"
    }

    private func testBitbucketConnection() {
        isBBTesting = true
        statusMessage = nil

        let baseURL = bitbucketURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseURL)/rest/api/1.0/users"

        guard let url = URL(string: urlString) else {
            statusIsError = true
            statusMessage = "Invalid server URL"
            isBBTesting = false
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
                let (_, response) = try await URLSession.shared.data(
                    for: request
                )
                guard let http = response as? HTTPURLResponse else {
                    statusIsError = true
                    statusMessage = "No response from server"
                    isBBTesting = false
                    return
                }

                if http.statusCode == 200 {
                    statusIsError = false
                    statusMessage = "Connected to Bitbucket Server"
                } else if http.statusCode == 401 {
                    statusIsError = true
                    statusMessage =
                        "Authentication failed — check your token"
                } else if http.statusCode == 403 {
                    statusIsError = true
                    statusMessage =
                        "Forbidden — token lacks permissions"
                } else {
                    statusIsError = true
                    statusMessage =
                        "HTTP \(http.statusCode) — check server URL"
                }
            } catch {
                statusIsError = true
                statusMessage =
                    "Connection failed: \(error.localizedDescription)"
            }
            isBBTesting = false
        }
    }

    private func saveConfig(type: IntegrationType, url: String, username: String) {
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
