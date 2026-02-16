import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case plugins = "Plugins"
    case integrations = "Integrations"
    case tickets = "Tickets"
    case patterns = "Patterns"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .plugins: "puzzlepiece.extension"
        case .integrations: "link"
        case .tickets: "ticket"
        case .patterns: "sparkles"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsTab = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsView()
            case .plugins:
                PluginSettingsView()
            case .integrations:
                IntegrationSettingsView()
            case .tickets:
                TicketSettingsView()
            case .patterns:
                LearnedPatternsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(width: 650, height: 450)
    }
}
