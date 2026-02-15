import Foundation
import SwiftData

@Model
final class TicketOverride {
    var id: UUID
    var project: String
    var branch: String
    var ticketID: String
    var createdAt: Date

    // 006: Extended matching patterns
    var urlPattern: String? = nil
    var appNamePattern: String? = nil
    var priority: Int = 0

    init(
        project: String,
        branch: String,
        ticketID: String,
        urlPattern: String? = nil,
        appNamePattern: String? = nil,
        priority: Int = 0
    ) {
        self.id = UUID()
        self.project = project
        self.branch = branch
        self.ticketID = ticketID
        self.createdAt = Date()
        self.urlPattern = urlPattern
        self.appNamePattern = appNamePattern
        self.priority = priority
    }
}
