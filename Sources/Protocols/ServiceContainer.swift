import SwiftUI
import SwiftData

// MARK: - Protocol

protocol ServiceContainerProtocol {
    func makeTodoService(context: ModelContext) -> any TodoServiceProtocol
    func makeProjectService(context: ModelContext) -> any ProjectServiceProtocol
    func makeTagService(context: ModelContext) -> any TagServiceProtocol

    func makeTimeEntryService() -> any TimeEntryServiceProtocol
    func makeExportService() -> any ExportServiceProtocol
    func makeLearnedPatternService() -> any LearnedPatternServiceProtocol

    var jiraService: (any JiraServiceProtocol)? { get }
    var bitbucketService: (any BitbucketServiceProtocol)? { get }
}

// MARK: - Live Implementation

struct LiveServiceContainer: ServiceContainerProtocol {
    let modelContainer: ModelContainer
    let logService: LogService?

    private let _jiraService: JiraService
    private let _bitbucketService: BitbucketService

    @MainActor
    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        self.modelContainer = modelContainer
        self.logService = logService
        self._jiraService = JiraService(
            modelContainer: modelContainer, logService: logService
        )
        self._bitbucketService = BitbucketService(
            modelContainer: modelContainer, logService: logService
        )
    }

    init(
        modelContainer: ModelContainer,
        logService: LogService?,
        jiraService: JiraService,
        bitbucketService: BitbucketService
    ) {
        self.modelContainer = modelContainer
        self.logService = logService
        self._jiraService = jiraService
        self._bitbucketService = bitbucketService
    }

    func makeTodoService(context: ModelContext) -> any TodoServiceProtocol {
        TodoService(context: context)
    }

    func makeProjectService(context: ModelContext) -> any ProjectServiceProtocol {
        ProjectService(context: context)
    }

    func makeTagService(context: ModelContext) -> any TagServiceProtocol {
        TagService(context: context)
    }

    func makeTimeEntryService() -> any TimeEntryServiceProtocol {
        TimeEntryService(modelContainer: modelContainer)
    }

    func makeExportService() -> any ExportServiceProtocol {
        ExportService(modelContainer: modelContainer)
    }

    func makeLearnedPatternService() -> any LearnedPatternServiceProtocol {
        LearnedPatternService(modelContainer: modelContainer)
    }

    var jiraService: (any JiraServiceProtocol)? { _jiraService }
    var bitbucketService: (any BitbucketServiceProtocol)? { _bitbucketService }
}

// MARK: - Environment Key

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue: (any ServiceContainerProtocol)? = nil
}

extension EnvironmentValues {
    var serviceContainer: (any ServiceContainerProtocol)? {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
