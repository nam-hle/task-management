import Foundation
import SwiftData

struct ProjectService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func create(
        name: String, color: String = "#007AFF", descriptionText: String = ""
    ) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyName }
        guard try !nameExists(trimmed) else {
            throw ValidationError.duplicateName(trimmed)
        }

        let project = Project(
            name: trimmed,
            color: color,
            descriptionText: descriptionText,
            sortOrder: try nextSortOrder()
        )
        context.insert(project)
        return project
    }

    func update(
        _ project: Project, name: String? = nil, color: String? = nil,
        descriptionText: String? = nil
    ) throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let exists = trimmed == project.name ? false : try nameExists(trimmed)
            let allowed = !trimmed.isEmpty && (trimmed == project.name || !exists)
            if allowed {
                project.name = trimmed
            }
        }
        if let color { project.color = color }
        if let descriptionText { project.descriptionText = descriptionText }
    }

    func delete(_ project: Project) {
        for todo in project.todos {
            todo.project = nil
        }
        context.delete(project)
    }

    func list() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    private func nameExists(_ name: String) throws -> Bool {
        let lowered = name.lowercased()
        let descriptor = FetchDescriptor<Project>()
        let all = try context.fetch(descriptor)
        return all.contains { $0.name.lowercased() == lowered }
    }

    private func nextSortOrder() throws -> Int {
        let projects = try list()
        return (projects.map(\.sortOrder).max() ?? -1) + 1
    }
}
