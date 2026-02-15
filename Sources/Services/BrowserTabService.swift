import Foundation
import AppKit
import ApplicationServices

struct BrowserTabInfo {
    let title: String
    let url: String?
}

struct BitbucketPRRef {
    let serverURL: String
    let projectKey: String
    let repoSlug: String
    let prNumber: Int
}

struct BitbucketPRDetail {
    let title: String
    let sourceBranch: String
    let ticketID: String?
}

enum BrowserTabService {
    private static let ticketPattern = try! Regex("[A-Z][A-Z0-9]+-\\d+")

    // MARK: - Chrome (AppleScript)

    static func readChromeTab() async -> BrowserTabInfo? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                tell application "Google Chrome"
                    if (count of windows) is 0 then return ""
                    set t to title of active tab of front window
                    set u to URL of active tab of front window
                    return t & "\\n" & u
                end tell
                """
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: nil)
                    return
                }
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                let output = result.stringValue ?? ""
                let parts = output.split(separator: "\n", maxSplits: 1)
                guard parts.count == 2 else {
                    continuation.resume(returning: nil)
                    return
                }
                let info = BrowserTabInfo(
                    title: String(parts[0]),
                    url: String(parts[1])
                )
                continuation.resume(returning: info)
            }
        }
    }

    // MARK: - Firefox (AXUIElement window title)

    static func readFirefoxWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "org.mozilla.firefox" && $0.isActive }
        ) else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow
        )
        guard result == .success, let window = focusedWindow else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue
        )
        guard titleResult == .success, let title = titleValue as? String else { return nil }

        // Strip browser suffix
        let suffixes = [" — Mozilla Firefox", " - Mozilla Firefox"]
        var cleaned = title
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break
            }
        }
        return cleaned
    }

    // MARK: - App Detection

    static func isAppInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) != nil
    }

    static func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID
        }
    }

    // MARK: - Jira URL Parsing

    /// Extracts ticket ID from a Jira URL like:
    /// `https://jira.example.com/browse/PROJ-123`
    /// `https://jira.example.com/jira/browse/PROJ-123`
    static func extractJiraTicketFromURL(_ url: String) -> String? {
        // Match /browse/TICKET-123 pattern
        guard let regex = try? Regex("/browse/([A-Z][A-Z0-9]+-\\d+)"),
              let match = url.firstMatch(of: regex),
              match.output.count > 1 else { return nil }
        return String(url[match.output[1].range!])
    }

    /// Extracts ticket ID from text (title, branch name, etc.)
    static func extractTicketID(from text: String) -> String? {
        guard let match = text.firstMatch(of: ticketPattern) else { return nil }
        return String(text[match.range])
    }

    // MARK: - Bitbucket URL Parsing

    /// Parses a Bitbucket Server PR URL:
    /// `https://bitbucket.example.com/projects/PROJ/repos/my-repo/pull-requests/42`
    static func parseBitbucketPRURL(_ url: String) -> BitbucketPRRef? {
        guard let regex = try? Regex(
            "(https?://[^/]+)/projects/([^/]+)/repos/([^/]+)/pull-requests/(\\d+)"
        ),
        let match = url.firstMatch(of: regex),
        match.output.count > 4 else { return nil }

        guard let prNum = Int(String(url[match.output[4].range!])) else { return nil }
        return BitbucketPRRef(
            serverURL: String(url[match.output[1].range!]),
            projectKey: String(url[match.output[2].range!]),
            repoSlug: String(url[match.output[3].range!]),
            prNumber: prNum
        )
    }

    // MARK: - Bitbucket REST API

    /// Fetches PR details from Bitbucket Server REST API.
    /// Uses credentials from IntegrationConfig + Keychain.
    static func fetchBitbucketPR(
        ref: BitbucketPRRef,
        username: String,
        token: String
    ) async -> BitbucketPRDetail? {
        let urlString = "\(ref.serverURL)/rest/api/1.0/projects/\(ref.projectKey)/repos/\(ref.repoSlug)/pull-requests/\(ref.prNumber)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        let credentials = Data("\(username):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let title = json["title"] as? String ?? ""
            let fromRef = json["fromRef"] as? [String: Any]
            let sourceBranch = fromRef?["displayId"] as? String ?? ""

            // Extract ticket from branch name first, then title
            let ticketID = extractTicketID(from: sourceBranch)
                ?? extractTicketID(from: title)

            return BitbucketPRDetail(
                title: title,
                sourceBranch: sourceBranch,
                ticketID: ticketID
            )
        } catch {
            print("Bitbucket API error: \(error)")
            return nil
        }
    }
}
