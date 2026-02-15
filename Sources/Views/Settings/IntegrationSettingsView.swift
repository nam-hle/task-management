import SwiftUI
import SwiftData

struct IntegrationSettingsView: View {
    @Query(sort: \IntegrationConfig.type.rawValue)
    private var configs: [IntegrationConfig]
    @Environment(\.modelContext) private var modelContext

    @State private var jiraURL = ""
    @State private var jiraUsername = ""
    @State private var jiraToken = ""
    @State private var bitbucketURL = ""
    @State private var bitbucketUsername = ""
    @State private var bitbucketToken = ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Jira") {
                TextField("Server URL", text: $jiraURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $jiraUsername)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Token", text: $jiraToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Jira Settings") {
                        saveJiraSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Section("Bitbucket") {
                TextField("Server URL", text: $bitbucketURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $bitbucketUsername)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Token", text: $bitbucketToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Bitbucket Settings") {
                        saveBitbucketSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
                        .foregroundStyle(.green)
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
        jiraUsername = jiraConfig?.username ?? ""
        jiraToken = KeychainService.retrieve(key: "jira_token") ?? ""

        let bbConfig = configs.first { $0.type == .bitbucket }
        bitbucketURL = bbConfig?.serverURL ?? ""
        bitbucketUsername = bbConfig?.username ?? ""
        bitbucketToken = KeychainService.retrieve(key: "bitbucket_token") ?? ""
    }

    private func saveJiraSettings() {
        saveConfig(type: .jira, url: jiraURL, username: jiraUsername)
        if !jiraToken.isEmpty {
            try? KeychainService.store(key: "jira_token", value: jiraToken)
        }
        statusMessage = "Jira settings saved"
    }

    private func saveBitbucketSettings() {
        saveConfig(type: .bitbucket, url: bitbucketURL, username: bitbucketUsername)
        if !bitbucketToken.isEmpty {
            try? KeychainService.store(key: "bitbucket_token", value: bitbucketToken)
        }
        statusMessage = "Bitbucket settings saved"
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
