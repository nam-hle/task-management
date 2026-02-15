import Foundation
import SwiftData

@Model
final class JiraLink {
    var id: UUID
    var ticketID: String
    var serverURL: String
    var cachedSummary: String?
    var cachedStatus: String?
    var cachedAssignee: String?
    var lastSyncedAt: Date?
    var isBroken: Bool

    var todo: Todo?

    init(
        ticketID: String,
        serverURL: String,
        todo: Todo? = nil
    ) {
        self.id = UUID()
        self.ticketID = ticketID
        self.serverURL = serverURL
        self.cachedSummary = nil
        self.cachedStatus = nil
        self.cachedAssignee = nil
        self.lastSyncedAt = nil
        self.isBroken = false
        self.todo = todo
    }
}
