import SwiftUI
import ApplicationServices

struct AccessibilityPermissionView: View {
    @State private var isGranted = AXIsProcessTrusted()
    @State private var pollTimer: Timer?
    var onPermissionGranted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("TaskManagement needs Accessibility permission to detect which application you're using and track your time automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                permissionStep(number: 1, text: "Click \"Open System Settings\" below")
                permissionStep(number: 2, text: "Find TaskManagement in the list")
                permissionStep(number: 3, text: "Toggle it on")
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Open System Settings") {
                openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 8) {
                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Permission granted!")
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permission...")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private func permissionStep(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())
            Text(text)
                .font(.callout)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let granted = AXIsProcessTrusted()
            if granted != isGranted {
                isGranted = granted
                if granted {
                    stopPolling()
                    onPermissionGranted()
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
