import Foundation
import SwiftData

// MARK: - Struct Service Mocks

struct MockTodoService: TodoServiceProtocol {
    var todosToReturn: [Todo] = []
    var trashedToReturn: [Todo] = []

    func create(
        title: String, descriptionText: String, priority: Priority,
        dueDate: Date?, project: Project?, tags: [Tag]
    ) throws -> Todo {
        Todo(
            title: title, descriptionText: descriptionText,
            priority: priority, dueDate: dueDate,
            project: project, tags: tags, sortOrder: 0
        )
    }

    func update(
        _ todo: Todo, title: String?, descriptionText: String?,
        priority: Priority?, dueDate: Date??,
        project: Project??, tags: [Tag]?
    ) {}

    func complete(_ todo: Todo) {}
    func reopen(_ todo: Todo) {}
    func toggleComplete(_ todo: Todo) {}
    func softDelete(_ todo: Todo) {}
    func restore(_ todo: Todo) {}
    func purgeExpired() throws -> Int { 0 }

    func list(
        project: Project?, tag: Tag?, priority: Priority?,
        isCompleted: Bool?, searchText: String, includeTrashed: Bool
    ) throws -> [Todo] {
        todosToReturn
    }

    func listTrashed() throws -> [Todo] { trashedToReturn }
    func reorder(_ todo: Todo, newSortOrder: Int) {}
}

struct MockProjectService: ProjectServiceProtocol {
    var projectsToReturn: [Project] = []

    func create(
        name: String, color: String, descriptionText: String
    ) throws -> Project {
        Project(name: name, color: color, descriptionText: descriptionText, sortOrder: 0)
    }

    func update(
        _ project: Project, name: String?, color: String?,
        descriptionText: String?
    ) throws {}

    func delete(_ project: Project) {}
    func list() throws -> [Project] { projectsToReturn }
}

struct MockTagService: TagServiceProtocol {
    var tagsToReturn: [Tag] = []

    func create(name: String, color: String) throws -> Tag {
        Tag(name: name, color: color)
    }

    func update(_ tag: Tag, name: String?, color: String?) throws {}
    func delete(_ tag: Tag) {}
    func list() throws -> [Tag] { tagsToReturn }
}

// MARK: - Actor Service Mocks

actor MockTimeEntryService: TimeEntryServiceProtocol {
    var entriesToReturn: [TimeEntry] = []

    func create(
        todoID: PersistentIdentifier?, applicationName: String?,
        applicationBundleID: String?, source: EntrySource,
        startTime: Date, label: String?, sourcePluginID: String?,
        ticketID: String?, contextMetadata: String?
    ) throws -> PersistentIdentifier {
        fatalError("MockTimeEntryService.create not configured")
    }

    func createFinalized(
        startTime: Date, endTime: Date, source: EntrySource,
        applicationName: String?, sourcePluginID: String?,
        ticketID: String?, contextMetadata: String?
    ) throws -> PersistentIdentifier {
        fatalError("MockTimeEntryService.createFinalized not configured")
    }

    func finalize(entryID: PersistentIdentifier, endTime: Date) throws {}
    func entries(for date: Date) throws -> [TimeEntry] { entriesToReturn }
    func inProgressEntries() throws -> [TimeEntry] { [] }
    func recoverInProgressEntries() throws -> Int { 0 }

    func merge(
        entryIDs: [PersistentIdentifier]
    ) throws -> PersistentIdentifier {
        fatalError("MockTimeEntryService.merge not configured")
    }

    func split(
        entryID: PersistentIdentifier, at splitTime: Date
    ) throws -> (PersistentIdentifier, PersistentIdentifier) {
        fatalError("MockTimeEntryService.split not configured")
    }

    func update(
        entryID: PersistentIdentifier, changes: TimeEntryChanges
    ) throws {}

    func markReviewed(entryIDs: [PersistentIdentifier]) throws {}
    func assignTicket(
        entryIDs: [PersistentIdentifier], ticketID: String
    ) throws {}

    func applyAutoApproval(
        entryID: PersistentIdentifier,
        patternID: PersistentIdentifier,
        todoID: PersistentIdentifier
    ) throws {}

    func purgeExpired(retentionDays: Int) throws -> Int { 0 }
    func deleteAll() throws {}
}

actor MockExportService: ExportServiceProtocol {
    var exportResultToReturn = ExportResult(
        formattedText: "Mock export", entryIDs: [], totalDuration: 0
    )

    func generateExport(for date: Date) throws -> ExportResult {
        exportResultToReturn
    }

    func checkDuplicates(entryIDs: [UUID]) throws -> [UUID] { [] }

    func confirmExport(
        result: ExportResult
    ) throws -> PersistentIdentifier {
        fatalError("MockExportService.confirmExport not configured")
    }

    func markBooked(exportID: PersistentIdentifier) throws {}
}

actor MockLearnedPatternService: LearnedPatternServiceProtocol {
    func findMatch(
        contextType: String, identifier: String
    ) throws -> PersistentIdentifier? {
        nil
    }

    func linkedTodoID(
        for patternID: PersistentIdentifier
    ) -> PersistentIdentifier? {
        nil
    }

    func learnFromReview(
        contextType: String, identifier: String,
        todoID: PersistentIdentifier
    ) throws {}

    func revoke(patternID: PersistentIdentifier) throws {}
    func flagStalePatterns() throws -> Int { 0 }
}

// MARK: - @MainActor Service Mocks

@MainActor @Observable
final class MockJiraService: JiraServiceProtocol {
    var ticketInfoToReturn: [String: JiraTicketInfo] = [:]

    func ticketInfo(for ticketID: String) async -> JiraTicketInfo? {
        ticketInfoToReturn[ticketID]
    }

    func prefetch(ticketID: String) {}
    func projectName(for projectKey: String) -> String? { nil }
}

@MainActor @Observable
final class MockBitbucketService: BitbucketServiceProtocol {
    var prInfoToReturn: [String: BitbucketPRInfo] = [:]

    func prInfo(for prURL: String) async -> BitbucketPRInfo? {
        prInfoToReturn[prURL]
    }

    func prefetch(prURL: String) {}
}
