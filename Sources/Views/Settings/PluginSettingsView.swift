import SwiftUI

struct PluginSettingsView: View {
    @Environment(TrackingCoordinator.self) private var coordinator

    var body: some View {
        Form {
            if let pluginManager = coordinator.pluginManager {
                let active = pluginManager.plugins.filter {
                    pluginManager.isEnabled(pluginID: $0.id)
                }
                let inactive = pluginManager.plugins.filter {
                    !pluginManager.isEnabled(pluginID: $0.id)
                }

                if !active.isEmpty {
                    Section("Active Plugins") {
                        ForEach(active, id: \.id) { plugin in
                            pluginRow(plugin: plugin, manager: pluginManager)
                        }
                    }
                }

                if !inactive.isEmpty {
                    Section("Inactive Plugins") {
                        ForEach(inactive, id: \.id) { plugin in
                            pluginRow(plugin: plugin, manager: pluginManager)
                        }
                    }
                }
            } else {
                Section {
                    Text("Plugin system not initialized")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pluginRow(
        plugin: any TimeTrackingPlugin, manager: PluginManager
    ) -> some View {
        HStack(spacing: 12) {
            statusDot(for: plugin.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.displayName)
                    .font(.headline)
                Text(plugin.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .error(let msg) = plugin.status {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if case .unavailable = plugin.status {
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if case .permissionRequired = plugin.status {
                Button("Grant Permission") {
                    openAccessibilitySettings()
                }
                .controlSize(.small)
            }

            Toggle("", isOn: Binding(
                get: { manager.isEnabled(pluginID: plugin.id) },
                set: { enabled in
                    Task {
                        if enabled {
                            await manager.enable(pluginID: plugin.id)
                        } else {
                            await manager.disable(pluginID: plugin.id)
                        }
                    }
                }
            ))
            .labelsHidden()
            .disabled(plugin.status == .unavailable)
        }
    }

    @ViewBuilder
    private func statusDot(for status: PluginStatus) -> some View {
        let color: Color = switch status {
        case .active: .green
        case .inactive: .gray
        case .error: .orange
        case .permissionRequired: .orange
        case .unavailable: .gray.opacity(0.5)
        }

        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}
