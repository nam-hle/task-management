import Foundation
import SwiftData

@MainActor
@Observable
final class FirefoxPlugin: BrowserTabTrackingPlugin {
    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        super.init(
            config: .firefox,
            modelContainer: modelContainer,
            logService: logService
        )
    }

    override func readCurrentTab() async -> BrowserTabInfo? {
        BrowserTabService.readFirefoxTab()
    }
}
