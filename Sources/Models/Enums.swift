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
    case autoDetected
    case wakatime
    case edited

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .timer: "Timer"
        case .autoDetected: "Auto-Detected"
        case .wakatime: "WakaTime"
        case .edited: "Edited"
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
}

enum TrackingState: Equatable {
    case idle
    case tracking
    case paused(reason: PauseReason)
    case permissionRequired
}

enum PauseReason: String, Codable, Equatable {
    case userPaused
    case systemIdle
    case systemSleep
    case screenLocked
    case manualTimerActive
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
