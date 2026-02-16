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
        var store = loadStore()
        store[key] = value
        let data = try JSONEncoder().encode(store)
        try data.write(to: credentialsURL, options: .atomic)
        setFilePermissions()
    }

    static func retrieve(
        key: String,
        service: String = ""
    ) -> String? {
        loadStore()[key]
    }

    static func delete(
        key: String,
        service: String = ""
    ) throws {
        var store = loadStore()
        store.removeValue(forKey: key)
        let data = try JSONEncoder().encode(store)
        try data.write(to: credentialsURL, options: .atomic)
        setFilePermissions()
    }

    private static func loadStore() -> [String: String] {
        guard let data = try? Data(contentsOf: credentialsURL),
              let store = try? JSONDecoder().decode(
                  [String: String].self, from: data
              )
        else { return [:] }
        return store
    }

    private static func setFilePermissions() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path
        )
    }
}
