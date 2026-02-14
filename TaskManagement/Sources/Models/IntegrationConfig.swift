import Foundation
import SwiftData

@Model
final class IntegrationConfig {
    var id: UUID
    var type: IntegrationType
    var serverURL: String
    var username: String
    var syncInterval: TimeInterval
    var isEnabled: Bool
    var lastSyncedAt: Date?

    init(
        type: IntegrationType,
        serverURL: String,
        username: String,
        syncInterval: TimeInterval = 900,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.type = type
        self.serverURL = serverURL
        self.username = username
        self.syncInterval = syncInterval
        self.isEnabled = isEnabled
        self.lastSyncedAt = nil
    }
}
