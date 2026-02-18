import Foundation
import SwiftData

struct TagService: TagServiceProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func create(name: String, color: String = "#8E8E93") throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyName }
        guard try !nameExists(trimmed) else {
            throw ValidationError.duplicateName(trimmed)
        }

        let tag = Tag(
            name: trimmed,
            color: color
        )
        context.insert(tag)
        return tag
    }

    func update(_ tag: Tag, name: String? = nil, color: String? = nil) throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let exists = trimmed == tag.name ? false : try nameExists(trimmed)
            let allowed = !trimmed.isEmpty && (trimmed == tag.name || !exists)
            if allowed {
                tag.name = trimmed
            }
        }
        if let color { tag.color = color }
    }

    func delete(_ tag: Tag) {
        for todo in tag.todos {
            todo.tags.removeAll { $0.id == tag.id }
        }
        context.delete(tag)
    }

    func list() throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    private func nameExists(_ name: String) throws -> Bool {
        let lowered = name.lowercased()
        let all = try list()
        return all.contains { $0.name.lowercased() == lowered }
    }
}
