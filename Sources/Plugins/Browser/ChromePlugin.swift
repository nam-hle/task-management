import Foundation
import SwiftData

@MainActor
@Observable
final class ChromePlugin: BrowserTabTrackingPlugin {
    init(modelContainer: ModelContainer, logService: LogService? = nil) {
        super.init(
            config: .chrome,
            modelContainer: modelContainer,
            logService: logService
        )
    }

    override func readCurrentTab() async -> BrowserTabInfo? {
        await BrowserTabService.readChromeTab()
    }
}
