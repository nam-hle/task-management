import Foundation
import SwiftData

@Model
final class ExportRecord {
    var id: UUID
    var exportedAt: Date
    var formattedOutput: String
    var entryCount: Int
    var totalDuration: TimeInterval
    var isBooked: Bool
    var bookedAt: Date?
    var timeEntryIDs: [UUID]

    init(
        exportedAt: Date = Date(),
        formattedOutput: String,
        entryCount: Int,
        totalDuration: TimeInterval,
        timeEntryIDs: [UUID]
    ) {
        self.id = UUID()
        self.exportedAt = exportedAt
        self.formattedOutput = formattedOutput
        self.entryCount = entryCount
        self.totalDuration = totalDuration
        self.isBooked = false
        self.timeEntryIDs = timeEntryIDs
    }
}
