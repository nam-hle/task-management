import Foundation
import SwiftData

// MARK: - Struct Service Protocols

protocol TodoServiceProtocol {
    func create(
        title: String,
        descriptionText: String,
        priority: Priority,
        dueDate: Date?,
        project: Project?,
        tags: [Tag]
    ) throws -> Todo

    func update(
        _ todo: Todo, title: String?, descriptionText: String?,
        priority: Priority?, dueDate: Date??,
        project: Project??, tags: [Tag]?
    )

    func complete(_ todo: Todo)
    func reopen(_ todo: Todo)
    func toggleComplete(_ todo: Todo)
    func softDelete(_ todo: Todo)
    func restore(_ todo: Todo)
    func purgeExpired() throws -> Int

    func list(
        project: Project?,
        tag: Tag?,
        priority: Priority?,
        isCompleted: Bool?,
        searchText: String,
        includeTrashed: Bool
    ) throws -> [Todo]

    func listTrashed() throws -> [Todo]
    func reorder(_ todo: Todo, newSortOrder: Int)
}

extension TodoServiceProtocol {
    func create(
        title: String,
        descriptionText: String = "",
        priority: Priority = .medium,
        dueDate: Date? = nil,
        project: Project? = nil,
        tags: [Tag] = []
    ) throws -> Todo {
        try create(
            title: title,
            descriptionText: descriptionText,
            priority: priority,
            dueDate: dueDate,
            project: project,
            tags: tags
        )
    }

    func update(
        _ todo: Todo, title: String? = nil, descriptionText: String? = nil,
        priority: Priority? = nil, dueDate: Date?? = nil,
        project: Project?? = nil, tags: [Tag]? = nil
    ) {
        update(
            todo, title: title, descriptionText: descriptionText,
            priority: priority, dueDate: dueDate,
            project: project, tags: tags
        )
    }

    func list(
        project: Project? = nil,
        tag: Tag? = nil,
        priority: Priority? = nil,
        isCompleted: Bool? = nil,
        searchText: String = "",
        includeTrashed: Bool = false
    ) throws -> [Todo] {
        try list(
            project: project,
            tag: tag,
            priority: priority,
            isCompleted: isCompleted,
            searchText: searchText,
            includeTrashed: includeTrashed
        )
    }
}

protocol ProjectServiceProtocol {
    func create(name: String, color: String, descriptionText: String) throws -> Project
    func update(_ project: Project, name: String?, color: String?, descriptionText: String?) throws
    func delete(_ project: Project)
    func list() throws -> [Project]
}

extension ProjectServiceProtocol {
    func create(
        name: String, color: String = "#007AFF", descriptionText: String = ""
    ) throws -> Project {
        try create(name: name, color: color, descriptionText: descriptionText)
    }

    func update(
        _ project: Project, name: String? = nil, color: String? = nil,
        descriptionText: String? = nil
    ) throws {
        try update(project, name: name, color: color, descriptionText: descriptionText)
    }
}

protocol TagServiceProtocol {
    func create(name: String, color: String) throws -> Tag
    func update(_ tag: Tag, name: String?, color: String?) throws
    func delete(_ tag: Tag)
    func list() throws -> [Tag]
}

extension TagServiceProtocol {
    func create(name: String, color: String = "#8E8E93") throws -> Tag {
        try create(name: name, color: color)
    }

    func update(_ tag: Tag, name: String? = nil, color: String? = nil) throws {
        try update(tag, name: name, color: color)
    }
}

// MARK: - Actor Service Protocols

protocol TimeEntryServiceProtocol: Actor {
    func create(
        todoID: PersistentIdentifier?,
        applicationName: String?,
        applicationBundleID: String?,
        source: EntrySource,
        startTime: Date,
        label: String?,
        sourcePluginID: String?,
        ticketID: String?,
        contextMetadata: String?
    ) throws -> PersistentIdentifier

    func createFinalized(
        startTime: Date,
        endTime: Date,
        source: EntrySource,
        applicationName: String?,
        sourcePluginID: String?,
        ticketID: String?,
        contextMetadata: String?
    ) throws -> PersistentIdentifier

    func finalize(entryID: PersistentIdentifier, endTime: Date) throws
    func entries(for date: Date) throws -> [TimeEntry]
    func inProgressEntries() throws -> [TimeEntry]
    func recoverInProgressEntries() throws -> Int

    func merge(entryIDs: [PersistentIdentifier]) throws -> PersistentIdentifier
    func split(
        entryID: PersistentIdentifier, at splitTime: Date
    ) throws -> (PersistentIdentifier, PersistentIdentifier)
    func update(entryID: PersistentIdentifier, changes: TimeEntryChanges) throws

    func markReviewed(entryIDs: [PersistentIdentifier]) throws
    func assignTicket(entryIDs: [PersistentIdentifier], ticketID: String) throws
    func applyAutoApproval(
        entryID: PersistentIdentifier,
        patternID: PersistentIdentifier,
        todoID: PersistentIdentifier
    ) throws

    func purgeExpired(retentionDays: Int) throws -> Int
    func deleteAll() throws
}

extension TimeEntryServiceProtocol {
    func create(
        todoID: PersistentIdentifier? = nil,
        applicationName: String? = nil,
        applicationBundleID: String? = nil,
        source: EntrySource = .manual,
        startTime: Date = Date(),
        label: String? = nil,
        sourcePluginID: String? = nil,
        ticketID: String? = nil,
        contextMetadata: String? = nil
    ) throws -> PersistentIdentifier {
        try create(
            todoID: todoID,
            applicationName: applicationName,
            applicationBundleID: applicationBundleID,
            source: source,
            startTime: startTime,
            label: label,
            sourcePluginID: sourcePluginID,
            ticketID: ticketID,
            contextMetadata: contextMetadata
        )
    }

    func createFinalized(
        startTime: Date,
        endTime: Date,
        source: EntrySource,
        applicationName: String? = nil,
        sourcePluginID: String? = nil,
        ticketID: String? = nil,
        contextMetadata: String? = nil
    ) throws -> PersistentIdentifier {
        try createFinalized(
            startTime: startTime,
            endTime: endTime,
            source: source,
            applicationName: applicationName,
            sourcePluginID: sourcePluginID,
            ticketID: ticketID,
            contextMetadata: contextMetadata
        )
    }

    func finalize(
        entryID: PersistentIdentifier, endTime: Date = Date()
    ) throws {
        try finalize(entryID: entryID, endTime: endTime)
    }

    func purgeExpired(retentionDays: Int = 90) throws -> Int {
        try purgeExpired(retentionDays: retentionDays)
    }
}

protocol ExportServiceProtocol: Actor {
    func generateExport(for date: Date) throws -> ExportResult
    func checkDuplicates(entryIDs: [UUID]) throws -> [UUID]
    func confirmExport(result: ExportResult) throws -> PersistentIdentifier
    func markBooked(exportID: PersistentIdentifier) throws
}

protocol LearnedPatternServiceProtocol: Actor {
    func findMatch(contextType: String, identifier: String) throws -> PersistentIdentifier?
    func linkedTodoID(for patternID: PersistentIdentifier) -> PersistentIdentifier?
    func learnFromReview(
        contextType: String, identifier: String, todoID: PersistentIdentifier
    ) throws
    func revoke(patternID: PersistentIdentifier) throws
    func flagStalePatterns() throws -> Int
}

// MARK: - @MainActor Service Protocols

@MainActor
protocol JiraServiceProtocol {
    func ticketInfo(for ticketID: String) async -> JiraTicketInfo?
    func prefetch(ticketID: String)
    func projectName(for projectKey: String) -> String?
}

@MainActor
protocol BitbucketServiceProtocol {
    func prInfo(for prURL: String) async -> BitbucketPRInfo?
    func prefetch(prURL: String)
}
