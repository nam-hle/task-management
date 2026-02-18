import Foundation

@MainActor
protocol TimeTrackingPlugin: AnyObject, Identifiable where ID == String {
    var id: String { get }
    var displayName: String { get }
    var status: PluginStatus { get }

    nonisolated func isAvailable() -> Bool
    func start() async throws
    func stop() async throws
    func sync() async
}

extension TimeTrackingPlugin {
    func sync() async {}
}

@MainActor
@Observable
final class PluginManager {
    private(set) var plugins: [any TimeTrackingPlugin] = []
    private let logService: LogService?

    init(logService: LogService? = nil) {
        self.logService = logService
    }

    func register(_ plugin: any TimeTrackingPlugin) {
        plugins.append(plugin)
    }

    func startAll() async {
        for plugin in plugins {
            guard isEnabled(pluginID: plugin.id), plugin.isAvailable() else { continue }
            do {
                try await plugin.start()
            } catch {
                logService?.log(
                    "Plugin \(plugin.id) failed to start: \(error)",
                    level: .error
                )
            }
        }
    }

    func stopAll() async {
        for plugin in plugins {
            do {
                try await plugin.stop()
            } catch {
                logService?.log(
                    "Plugin \(plugin.id) failed to stop: \(error)",
                    level: .error
                )
            }
        }
    }

    func enable(pluginID: String) async {
        UserDefaults.standard.set(true, forKey: enabledKey(for: pluginID))
        guard let plugin = plugin(id: pluginID),
              plugin.isAvailable() else { return }
        do {
            try await plugin.start()
        } catch {
            logService?.log(
                "Plugin \(pluginID) failed to start: \(error)",
                level: .error
            )
        }
    }

    func disable(pluginID: String) async {
        UserDefaults.standard.set(false, forKey: enabledKey(for: pluginID))
        guard let plugin = plugin(id: pluginID) else { return }
        do {
            try await plugin.stop()
        } catch {
            logService?.log(
                "Plugin \(pluginID) failed to stop: \(error)",
                level: .error
            )
        }
    }

    func isEnabled(pluginID: String) -> Bool {
        let key = enabledKey(for: pluginID)
        if UserDefaults.standard.object(forKey: key) == nil {
            // Defaults: all plugins enabled
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    func plugin(id: String) -> (any TimeTrackingPlugin)? {
        plugins.first { $0.id == id }
    }

    func syncAll() async {
        for plugin in plugins where isEnabled(pluginID: plugin.id) {
            await plugin.sync()
        }
    }

    private func enabledKey(for pluginID: String) -> String {
        "plugin.\(pluginID).enabled"
    }
}
