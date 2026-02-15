import SwiftUI

struct MenuBarView: View {
    @Environment(TrackingCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @State private var manualTimerLabel = ""
    @State private var showManualTimerInput = false

    var body: some View {
        VStack(spacing: 12) {
            if case .tracking = coordinator.state {
                VStack(spacing: 4) {
                    Text(coordinator.currentAppName ?? "Tracking")
                        .font(.headline)
                        .lineLimit(2)
                    Text(formatElapsed(coordinator.elapsedSeconds))
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if coordinator.isManualTimerActive {
                    Button("Stop Timer") {
                        coordinator.stopManualTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Button("Pause") {
                        coordinator.pause(reason: .userPaused)
                    }
                    .buttonStyle(.bordered)
                }
            } else if case .paused(let reason) = coordinator.state {
                VStack(spacing: 4) {
                    Text("Paused")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(pauseReasonText(reason))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Resume") {
                    coordinator.resume()
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Tracking active")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if showManualTimerInput {
                HStack {
                    TextField("Timer label", text: $manualTimerLabel)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { startManualTimer() }
                    Button("Start") { startManualTimer() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Button("Manual Timer...") {
                    showManualTimerInput = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            Divider()

            Button("Open TaskManagement") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first(
                    where: { $0.canBecomeMain }
                ) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            }
            .buttonStyle(.plain)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
    }

    private func startManualTimer() {
        let label = manualTimerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        coordinator.startManualTimer(
            label: label.isEmpty ? nil : label
        )
        manualTimerLabel = ""
        showManualTimerInput = false
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func pauseReasonText(_ reason: PauseReason) -> String {
        switch reason {
        case .userPaused: "User paused"
        case .systemIdle: "System idle"
        case .systemSleep: "System sleeping"
        case .screenLocked: "Screen locked"
        case .manualTimerActive: "Manual timer active"
        }
    }
}
