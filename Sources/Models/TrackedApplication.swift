import Foundation
import SwiftData

@Model
final class TrackedApplication {
    var id: UUID
    var name: String
    var bundleIdentifier: String
    var isBrowser: Bool
    var isPreConfigured: Bool
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date

    init(
        name: String,
        bundleIdentifier: String,
        isBrowser: Bool = false,
        isPreConfigured: Bool = false,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isBrowser = isBrowser
        self.isPreConfigured = isPreConfigured
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
