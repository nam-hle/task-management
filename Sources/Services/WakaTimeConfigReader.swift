import Foundation

struct WakaTimeConfigReader {
    static func readAPIKey() -> String? {
        let configPath = NSString("~/.wakatime.cfg").expandingTildeInPath
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        var inSettingsSection = false
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                inSettingsSection = trimmed.lowercased() == "[settings]"
                continue
            }

            if inSettingsSection, trimmed.hasPrefix("api_key") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[1].trimmingCharacters(in: .whitespaces)
                    return key.isEmpty ? nil : key
                }
            }
        }

        return nil
    }
}
