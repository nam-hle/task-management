import Foundation

enum Priority: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }
}

enum BookingStatus: String, Codable, CaseIterable, Identifiable {
    case unreviewed
    case reviewed
    case exported

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .reviewed: "Reviewed"
        case .exported: "Exported"
        }
    }
}

enum EntrySource: String, Codable, CaseIterable, Identifiable {
    case manual
    case timer
    case autoDetected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .timer: "Timer"
        case .autoDetected: "Auto-Detected"
        }
    }
}

enum IntegrationType: String, Codable, CaseIterable, Identifiable {
    case jira
    case bitbucket

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jira: "Jira"
        case .bitbucket: "Bitbucket"
        }
    }
}
