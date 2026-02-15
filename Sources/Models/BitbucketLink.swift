import Foundation
import SwiftData

@Model
final class BitbucketLink {
    var id: UUID
    var repositorySlug: String
    var prNumber: Int
    var serverURL: String
    var cachedTitle: String?
    var cachedStatus: String?
    var cachedAuthor: String?
    var cachedReviewers: String?
    var lastSyncedAt: Date?
    var isBroken: Bool

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
        self.cachedTitle = nil
        self.cachedStatus = nil
        self.cachedAuthor = nil
        self.cachedReviewers = nil
        self.lastSyncedAt = nil
        self.isBroken = false
        self.todo = todo
    }
}
