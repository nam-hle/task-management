import Foundation
import SwiftData

@Model
final class JiraLink {
    var id: UUID
    var ticketID: String
    var serverURL: String

    var todo: Todo?

    init(
        ticketID: String,
        serverURL: String,
        todo: Todo? = nil
    ) {
        self.id = UUID()
        self.ticketID = ticketID
        self.serverURL = serverURL
        self.todo = todo
    }
}
