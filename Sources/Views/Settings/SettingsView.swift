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

            IntegrationSettingsView()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }

            LearnedPatternsView()
                .tabItem {
                    Label("Patterns", systemImage: "sparkles")
                }
        }
        .frame(width: 550, height: 450)
    }
}
