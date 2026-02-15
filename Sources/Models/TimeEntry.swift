import Foundation
import SwiftData

@Model
final class TimeEntry {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    var notes: String
    var bookingStatus: BookingStatus
    var source: EntrySource
    var isInProgress: Bool
    var createdAt: Date

    // 005: Application tracking fields
    var applicationName: String?
    var applicationBundleID: String?
    var label: String?

    // 006: Plugin system fields
    var sourcePluginID: String? = nil
    var ticketID: String? = nil
    var contextMetadata: String? = nil

    // Exclusion
    var isExcluded: Bool = false

    // 008: Learned patterns
    var isAutoApproved: Bool = false
    var learnedPattern: LearnedPattern?

    var todo: Todo?

    var formattedDuration: String {
        let totalSeconds = Int(effectiveDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    var effectiveDuration: TimeInterval {
        if isInProgress {
            return Date().timeIntervalSince(startTime)
        }
        return duration
    }

    init(
        startTime: Date,
        endTime: Date? = nil,
        duration: TimeInterval = 0,
        notes: String = "",
        bookingStatus: BookingStatus = .unreviewed,
        source: EntrySource = .manual,
        isInProgress: Bool = false,
        todo: Todo? = nil,
        applicationName: String? = nil,
        applicationBundleID: String? = nil,
        label: String? = nil,
        isAutoApproved: Bool = false,
        sourcePluginID: String? = nil,
        ticketID: String? = nil,
        contextMetadata: String? = nil
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.notes = notes
        self.bookingStatus = bookingStatus
        self.source = source
        self.isInProgress = isInProgress
        self.createdAt = Date()
        self.todo = todo
        self.applicationName = applicationName
        self.applicationBundleID = applicationBundleID
        self.label = label
        self.isAutoApproved = isAutoApproved
        self.sourcePluginID = sourcePluginID
        self.ticketID = ticketID
        self.contextMetadata = contextMetadata
    }
}
