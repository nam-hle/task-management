import Foundation
import SwiftData

@Model
final class Todo {
    var id: UUID
    var title: String
    var descriptionText: String
    var priority: Priority
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var sortOrder: Int

    @Relationship(inverse: \Project.todos)
    var project: Project?

    @Relationship(inverse: \Tag.todos)
    var tags: [Tag]

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.todo)
    var timeEntries: [TimeEntry]

    @Relationship(deleteRule: .cascade, inverse: \JiraLink.todo)
    var jiraLink: JiraLink?

    @Relationship(deleteRule: .cascade, inverse: \BitbucketLink.todo)
    var bitbucketLink: BitbucketLink?

    var isActive: Bool { !isCompleted && deletedAt == nil }
    var isTrashed: Bool { deletedAt != nil }

    init(
        title: String,
        descriptionText: String = "",
        priority: Priority = .medium,
        dueDate: Date? = nil,
        project: Project? = nil,
        tags: [Tag] = [],
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.descriptionText = descriptionText
        self.priority = priority
        self.dueDate = dueDate
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.sortOrder = sortOrder
        self.project = project
        self.tags = tags
        self.timeEntries = []
        self.jiraLink = nil
        self.bitbucketLink = nil
    }
}
