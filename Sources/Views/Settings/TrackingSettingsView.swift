import SwiftUI

struct TrackingSettingsView: View {
    @AppStorage("idleThresholdSeconds") private var idleThreshold: Double = 300
    @AppStorage("minimumSwitchDuration") private var minSwitchDuration: Double = 30
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 60

    var body: some View {
        Form {
            Section("Idle Detection") {
                HStack {
                    Text("Idle timeout")
                    Spacer()
                    Text(formatDuration(idleThreshold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $idleThreshold,
                    in: 60...1800,
                    step: 30
                )
                Text("Time without input before tracking pauses.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Application Switching") {
                HStack {
                    Text("Minimum switch duration")
                    Spacer()
                    Text(formatDuration(minSwitchDuration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $minSwitchDuration,
                    in: 5...120,
                    step: 5
                )
                Text("Brief app switches shorter than this are ignored.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Auto-Save") {
                HStack {
                    Text("Save interval")
                    Spacer()
                    Text(formatDuration(autoSaveInterval))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $autoSaveInterval,
                    in: 15...300,
                    step: 15
                )
                Text("How often in-progress entries are saved to prevent data loss.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 && secs > 0 {
            return "\(mins)m \(secs)s"
        } else if mins > 0 {
            return "\(mins)m"
        }
        return "\(Int(seconds))s"
    }
}
