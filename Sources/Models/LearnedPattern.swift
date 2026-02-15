import Foundation
import SwiftData

@Model
final class LearnedPattern {
    var id: UUID
    var contextType: String
    var identifierValue: String
    var linkedTodo: Todo?
    var confirmationCount: Int
    var lastConfirmedAt: Date
    var isActive: Bool
    var createdAt: Date

    init(
        contextType: String,
        identifierValue: String,
        linkedTodo: Todo? = nil,
        confirmationCount: Int = 1
    ) {
        self.id = UUID()
        self.contextType = contextType
        self.identifierValue = identifierValue
        self.linkedTodo = linkedTodo
        self.confirmationCount = confirmationCount
        self.lastConfirmedAt = Date()
        self.isActive = true
        self.createdAt = Date()
    }
}
