import Foundation
import SwiftData

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
    case booked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .reviewed: "Reviewed"
        case .exported: "Exported"
        case .booked: "Booked"
        }
    }
}

enum EntrySource: String, Codable, CaseIterable, Identifiable {
    case manual
    case timer
    case wakatime
    case edited
    case chrome
    case firefox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .timer: "Timer"
        case .wakatime: "WakaTime"
        case .edited: "Edited"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = EntrySource(rawValue: raw) ?? .manual
    }
}

// MARK: - Plugin Status

enum PluginStatus: Equatable {
    case active
    case inactive
    case error(String)
    case permissionRequired
    case unavailable

    var label: String {
        switch self {
        case .active: "Active"
        case .inactive: "Inactive"
        case .error: "Error"
        case .permissionRequired: "Permission Required"
        case .unavailable: "Unavailable"
        }
    }
}


struct TimeEntryChanges {
    var startTime: Date?
    var endTime: Date?
    var notes: String?
    var todoID: PersistentIdentifier?
    var removeTodo: Bool = false
    var bookingStatus: BookingStatus?
    var ticketID: String?
    var removeTicketID: Bool = false
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
