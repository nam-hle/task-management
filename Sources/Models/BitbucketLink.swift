import Foundation
import SwiftData

@Model
final class BitbucketLink {
    var id: UUID
    var repositorySlug: String
    var prNumber: Int
    var serverURL: String

    var todo: Todo?

    init(
        repositorySlug: String,
        prNumber: Int,
        serverURL: String,
        todo: Todo? = nil
    ) {
        self.id = UUID()
        self.repositorySlug = repositorySlug
        self.prNumber = prNumber
        self.serverURL = serverURL
        self.todo = todo
    }
}
