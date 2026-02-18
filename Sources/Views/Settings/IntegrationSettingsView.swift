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
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                integrationCard(
                    title: "Jira",
                    icon: "list.clipboard",
                    iconColor: .blue,
                    urlLabel: "Server URL",
                    urlHint: "e.g. https://jira.company.com/jira",
                    url: $jiraURL,
                    token: $jiraToken,
                    status: jiraStatus,
                    onTest: testJiraConnection
                )

                integrationCard(
                    title: "Bitbucket",
                    icon: "arrow.triangle.branch",
                    iconColor: .blue,
                    urlLabel: "Server URL",
                    urlHint: "e.g. https://bitbucket.company.com",
                    url: $bitbucketURL,
                    token: $bitbucketToken,
                    status: bbStatus,
                    onTest: testBitbucketConnection
                )

                Spacer()
            }
            .padding()
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: jiraURL) { debouncedSaveJira() }
        .onChange(of: jiraToken) { debouncedSaveJira() }
        .onChange(of: bitbucketURL) { debouncedSaveBitbucket() }
        .onChange(of: bitbucketToken) { debouncedSaveBitbucket() }
        .onAppear { loadSettings() }
    }

    // MARK: - Integration Card

    private func integrationCard(
        title: String,
        icon: String,
        iconColor: Color,
        urlLabel: String,
        urlHint: String,
        url: Binding<String>,
        token: Binding<String>,
        status: ConnectionStatus?,
        onTest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.headline)

                Spacer()

                statusBadge(status)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(urlLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(urlHint, text: url)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Access Token")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("Enter token", text: token)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Test Connection") { onTest() }
                    .controlSize(.small)
                    .disabled(
                        url.wrappedValue.isEmpty
                        || token.wrappedValue.isEmpty
                        || status == .testing
                    )

                if status == .testing {
                    ProgressView()
                        .controlSize(.small)
                }

                if case .error(let message) = status {
                    Spacer()
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: ConnectionStatus?) -> some View {
        switch status {
        case .connected(let message):
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(message)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.green.opacity(0.1))
            .clipShape(Capsule())
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Testing")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.1))
            .clipShape(Capsule())
        case .error:
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text("Error")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red.opacity(0.1))
            .clipShape(Capsule())
        case nil:
            if true {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.08))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Load & Save

    private func loadSettings() {
        let jiraConfig = configs.first { $0.type == .jira }
        jiraURL = jiraConfig?.serverURL ?? ""
        jiraToken = (try? KeychainService.retrieve(key: "jira_token")) ?? ""

        let bbConfig = configs.first { $0.type == .bitbucket }
        bitbucketURL = bbConfig?.serverURL ?? ""
        bitbucketToken =
            (try? KeychainService.retrieve(key: "bitbucket_token")) ?? ""

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
                do {
                    try KeychainService.store(
                        key: "jira_token", value: jiraToken
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
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
                do {
                    try KeychainService.store(
                        key: "bitbucket_token", value: bitbucketToken
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
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
                    let username = http.value(
                        forHTTPHeaderField: "X-AUSERNAME"
                    )
                    if let username, !username.isEmpty {
                        let displayName = await fetchBBDisplayName(
                            baseURL: baseURL, username: username
                        )
                        bbStatus = .connected(
                            "Connected as \(displayName ?? username)"
                        )
                    } else {
                        bbStatus = .connected("Connected")
                    }
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

    private func fetchBBDisplayName(
        baseURL: String, username: String
    ) async -> String? {
        guard let url = URL(
            string: "\(baseURL)/rest/api/1.0/users/\(username)"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(
            "application/json", forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Bearer \(bitbucketToken)",
            forHTTPHeaderField: "Authorization"
        )

        guard let (data, _) = try? await URLSession.shared.data(
            for: request
        ),
            let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let displayName = json["displayName"] as? String
        else { return nil }

        return displayName
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
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ConnectionStatus: Equatable {
    case connected(String)
    case error(String)
    case testing
}
