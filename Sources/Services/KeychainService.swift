import Foundation

struct KeychainService {
    private static let credentialsURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent(
            "TaskManagement", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("credentials.json")
    }()

    static func store(
        key: String,
        value: String,
        service: String = ""
    ) throws {
        var store = try loadStore()
        store[key] = value
        let data = try JSONEncoder().encode(store)
        try data.write(to: credentialsURL, options: .atomic)
        try setFilePermissions()
    }

    static func retrieve(
        key: String,
        service: String = ""
    ) throws -> String? {
        try loadStore()[key]
    }

    static func delete(
        key: String,
        service: String = ""
    ) throws {
        var store = try loadStore()
        store.removeValue(forKey: key)
        let data = try JSONEncoder().encode(store)
        try data.write(to: credentialsURL, options: .atomic)
        try setFilePermissions()
    }

    private static func loadStore() throws -> [String: String] {
        guard FileManager.default.fileExists(
            atPath: credentialsURL.path
        ) else { return [:] }
        let data = try Data(contentsOf: credentialsURL)
        return try JSONDecoder().decode(
            [String: String].self, from: data
        )
    }

    private static func setFilePermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path
        )
    }
}
