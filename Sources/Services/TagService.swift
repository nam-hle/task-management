import Foundation
import SwiftData

struct TagService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func create(name: String, color: String = "#8E8E93") -> Tag? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !nameExists(name) else { return nil }

        let tag = Tag(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color
        )
        context.insert(tag)
        return tag
    }

    func update(_ tag: Tag, name: String? = nil, color: String? = nil) {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && (trimmed == tag.name || !nameExists(trimmed)) {
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

    func list() -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func nameExists(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let all = list()
        return all.contains { $0.name.lowercased() == lowered }
    }
}
