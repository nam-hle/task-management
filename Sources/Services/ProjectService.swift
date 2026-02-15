import Foundation
import SwiftData

struct ProjectService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func create(name: String, color: String = "#007AFF", descriptionText: String = "") -> Project? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !nameExists(name) else { return nil }

        let project = Project(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            descriptionText: descriptionText,
            sortOrder: nextSortOrder()
        )
        context.insert(project)
        return project
    }

    func update(_ project: Project, name: String? = nil, color: String? = nil,
                descriptionText: String? = nil) {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && (trimmed == project.name || !nameExists(trimmed)) {
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

    func list() -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func nameExists(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let descriptor = FetchDescriptor<Project>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.contains { $0.name.lowercased() == lowered }
    }

    private func nextSortOrder() -> Int {
        let projects = list()
        return (projects.map(\.sortOrder).max() ?? -1) + 1
    }
}
