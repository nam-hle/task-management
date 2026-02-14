import SwiftUI

struct MenuBarView: View {
    @Environment(TimerManager.self) private var timerManager

    var body: some View {
        VStack(spacing: 12) {
            if timerManager.isRunning, let title = timerManager.activeTodoTitle {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(timerManager.formatElapsed(timerManager.elapsedSeconds))
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Stop") {
                        // Will be wired in US4
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Text("No active timer")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
