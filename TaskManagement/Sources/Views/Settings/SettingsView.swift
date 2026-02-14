import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TrackedAppsSettingsView()
                .tabItem {
                    Label("Tracked Apps", systemImage: "app.badge.checkmark")
                }

            TrackingSettingsView()
                .tabItem {
                    Label("Tracking", systemImage: "timer")
                }
        }
        .frame(width: 500, height: 400)
    }
}
