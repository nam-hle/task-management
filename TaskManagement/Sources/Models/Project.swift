import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var color: String
    var descriptionText: String
    var sortOrder: Int
    var createdAt: Date

    var todos: [Todo]

    init(
        name: String,
        color: String = "#007AFF",
        descriptionText: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.descriptionText = descriptionText
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.todos = []
    }
}
