import SwiftUI
import SwiftData

struct TimeTrackingDashboard: View {
    @State private var selectedTab = "tickets"

    var body: some View {
        TabView(selection: $selectedTab) {
            TicketsView()
                .tabItem {
                    Label("Tickets", systemImage: "ticket")
                }
                .tag("tickets")

            ExportView()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag("export")
        }
        .navigationTitle("Time Tracking")
    }
}
