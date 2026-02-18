import Foundation

enum AppConfig {
    enum Keys {
        static let idleThresholdSeconds = "idleThresholdSeconds"
        static let minimumSwitchDuration = "minimumSwitchDuration"
        static let autoSaveInterval = "autoSaveInterval"
        static let browserPollInterval = "browserPollInterval"
        static let browserMinDuration = "browserMinDuration"
        static let wakatimeSyncInterval = "wakatimeSyncInterval"
        static let dataRetentionDays = "dataRetentionDays"
        static let todoPurgeDays = "todoPurgeDays"
        static let bitbucketCacheTTL = "bitbucketCacheTTL"
        static let jiraCacheTTL = "jiraCacheTTL"
        static let maxLogEntries = "maxLogEntries"
    }

    enum Defaults {
        static let idleThresholdSeconds: Double = 300
        static let minimumSwitchDuration: Double = 30
        static let autoSaveInterval: Double = 60
        static let browserPollInterval: Double = 5
        static let browserMinDuration: Double = 10
        static let wakatimeSyncInterval: Double = 300
        static let dataRetentionDays: Double = 90
        static let todoPurgeDays: Double = 30
        static let bitbucketCacheTTL: Double = 86_400
        static let jiraCacheTTL: Double = 300
        static let maxLogEntries: Int = 200
    }

    // MARK: - User-Configurable (exposed in Settings UI)

    static var browserPollInterval: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Keys.browserPollInterval)
        return val > 0 ? val : Defaults.browserPollInterval
    }

    static var browserMinDuration: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Keys.browserMinDuration)
        return val > 0 ? val : Defaults.browserMinDuration
    }

    static var wakatimeSyncInterval: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Keys.wakatimeSyncInterval)
        return val > 0 ? val : Defaults.wakatimeSyncInterval
    }

    static var dataRetentionDays: Int {
        let val = UserDefaults.standard.double(forKey: Keys.dataRetentionDays)
        return val > 0 ? Int(val) : Int(Defaults.dataRetentionDays)
    }

    static var todoPurgeDays: Int {
        let val = UserDefaults.standard.double(forKey: Keys.todoPurgeDays)
        return val > 0 ? Int(val) : Int(Defaults.todoPurgeDays)
    }

    // MARK: - Internal (centralized only, not in Settings UI)

    static var bitbucketCacheTTL: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Keys.bitbucketCacheTTL)
        return val > 0 ? val : Defaults.bitbucketCacheTTL
    }

    static var jiraCacheTTL: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Keys.jiraCacheTTL)
        return val > 0 ? val : Defaults.jiraCacheTTL
    }

    static var maxLogEntries: Int {
        let val = UserDefaults.standard.integer(forKey: Keys.maxLogEntries)
        return val > 0 ? val : Defaults.maxLogEntries
    }
}
