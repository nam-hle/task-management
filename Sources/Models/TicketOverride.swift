import Foundation
import SwiftData

@Model
final class TicketOverride {
    var id: UUID
    var project: String
    var branch: String
    var ticketID: String
    var createdAt: Date

    init(project: String, branch: String, ticketID: String) {
        self.id = UUID()
        self.project = project
        self.branch = branch
        self.ticketID = ticketID
        self.createdAt = Date()
    }
}
