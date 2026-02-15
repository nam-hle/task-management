import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PluginSettingsView()
                .tabItem {
                    Label("Plugins", systemImage: "puzzlepiece.extension")
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
