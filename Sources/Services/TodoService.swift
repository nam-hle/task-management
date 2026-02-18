import Foundation
import SwiftData

struct TodoService: TodoServiceProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func create(
        title: String,
        descriptionText: String = "",
        priority: Priority = .medium,
        dueDate: Date? = nil,
        project: Project? = nil,
        tags: [Tag] = []
    ) throws -> Todo {
        let todo = Todo(
            title: title,
            descriptionText: descriptionText,
            priority: priority,
            dueDate: dueDate,
            project: project,
            tags: tags,
            sortOrder: try nextSortOrder(in: project)
        )
        context.insert(todo)
        return todo
    }

    func update(_ todo: Todo, title: String? = nil, descriptionText: String? = nil,
                priority: Priority? = nil, dueDate: Date?? = nil,
                project: Project?? = nil, tags: [Tag]? = nil) {
        if let title { todo.title = title }
        if let descriptionText { todo.descriptionText = descriptionText }
        if let priority { todo.priority = priority }
        if let dueDate { todo.dueDate = dueDate }
        if let project { todo.project = project }
        if let tags { todo.tags = tags }
        todo.updatedAt = Date()
    }

    func complete(_ todo: Todo) {
        todo.isCompleted = true
        todo.completedAt = Date()
        todo.updatedAt = Date()
    }

    func reopen(_ todo: Todo) {
        todo.isCompleted = false
        todo.completedAt = nil
        todo.updatedAt = Date()
    }

    func toggleComplete(_ todo: Todo) {
        if todo.isCompleted {
            reopen(todo)
        } else {
            complete(todo)
        }
    }

    func softDelete(_ todo: Todo) {
        todo.deletedAt = Date()
        todo.updatedAt = Date()
    }

    func restore(_ todo: Todo) {
        todo.deletedAt = nil
        todo.updatedAt = Date()
    }

    func purgeExpired() throws -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { todo in
                todo.deletedAt != nil && todo.deletedAt! < cutoff
            }
        )
        let expired = try context.fetch(descriptor)
        let count = expired.count
        for todo in expired {
            context.delete(todo)
        }
        return count
    }

    func list(
        project: Project? = nil,
        tag: Tag? = nil,
        priority: Priority? = nil,
        isCompleted: Bool? = nil,
        searchText: String = "",
        includeTrashed: Bool = false
    ) throws -> [Todo] {
        var descriptor = FetchDescriptor<Todo>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        )

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        descriptor.predicate = #Predicate<Todo> { todo in
            (includeTrashed || todo.deletedAt == nil)
        }

        var results = try context.fetch(descriptor)

        if let project {
            let projectID = project.id
            results = results.filter { $0.project?.id == projectID }
        }

        if let tag {
            let tagID = tag.id
            results = results.filter { todo in
                todo.tags.contains { $0.id == tagID }
            }
        }

        if let priority {
            results = results.filter { $0.priority == priority }
        }

        if let isCompleted {
            results = results.filter { $0.isCompleted == isCompleted }
        }

        if !trimmedSearch.isEmpty {
            results = results.filter { todo in
                todo.title.lowercased().contains(trimmedSearch)
                    || todo.descriptionText.lowercased().contains(trimmedSearch)
            }
        }

        return results
    }

    func listTrashed() throws -> [Todo] {
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { $0.deletedAt != nil },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func reorder(_ todo: Todo, newSortOrder: Int) {
        todo.sortOrder = newSortOrder
        todo.updatedAt = Date()
    }

    private func nextSortOrder(in project: Project?) throws -> Int {
        let todos = try list(project: project, isCompleted: false)
        return (todos.map(\.sortOrder).max() ?? -1) + 1
    }
}
