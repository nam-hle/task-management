import Foundation
import SwiftData

struct MockServiceContainer: ServiceContainerProtocol {
    var todoService = MockTodoService()
    var projectService = MockProjectService()
    var tagService = MockTagService()

    var timeEntryService = MockTimeEntryService()
    var exportService = MockExportService()
    var learnedPatternService = MockLearnedPatternService()

    var mockJiraService: MockJiraService?
    var mockBitbucketService: MockBitbucketService?

    func makeTodoService(context: ModelContext) -> any TodoServiceProtocol {
        todoService
    }

    func makeProjectService(context: ModelContext) -> any ProjectServiceProtocol {
        projectService
    }

    func makeTagService(context: ModelContext) -> any TagServiceProtocol {
        tagService
    }

    func makeTimeEntryService() -> any TimeEntryServiceProtocol {
        timeEntryService
    }

    func makeExportService() -> any ExportServiceProtocol {
        exportService
    }

    func makeLearnedPatternService() -> any LearnedPatternServiceProtocol {
        learnedPatternService
    }

    var jiraService: (any JiraServiceProtocol)? { mockJiraService }
    var bitbucketService: (any BitbucketServiceProtocol)? { mockBitbucketService }
}
