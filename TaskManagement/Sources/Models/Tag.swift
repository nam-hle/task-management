import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var color: String

    var todos: [Todo]

    init(
        name: String,
        color: String = "#8E8E93"
    ) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.todos = []
    }
}
