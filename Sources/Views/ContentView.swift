import SwiftUI
import SwiftData

enum NavigationItem: Hashable {
    case todos(SidebarFilter)
    case timeTracking
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.logService) private var logService
    @State private var sidebarSelection: NavigationItem? = .timeTracking
    @State private var selectedTodo: Todo?
    @State private var showLogPanel = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: Binding(
                    get: { sidebarFilter },
                    set: { newFilter in
                        if let filter = newFilter {
                            sidebarSelection = .todos(filter)
                        }
                    }
                ),
                navigationSelection: $sidebarSelection
            )
        } detail: {
            switch sidebarSelection {
            case .todos(let filter):
                todoSplitView(filter: filter)
            case .timeTracking:
                TimeTrackingDashboard()
            case nil:
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showLogPanel, let logService {
                LogPanelView(logService: logService)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showLogPanel.toggle()
                } label: {
                    Image(systemName: "terminal")
                }
                .help("Toggle Log Panel")
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            selectedTodo = nil
        }
    }

    private func todoSplitView(filter: SidebarFilter) -> some View {
        HSplitView {
            TodoListView(selectedTodo: $selectedTodo, filter: filter)
                .navigationTitle(filterTitle(filter))
                .frame(minWidth: 250, idealWidth: 300)

            Group {
                if let todo = selectedTodo {
                    TodoDetailView(todo: todo)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.quaternary)
                        Text("Select a todo to view details")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
    }

    private var sidebarFilter: SidebarFilter? {
        if case .todos(let filter) = sidebarSelection {
            return filter
        }
        return nil
    }

    private func filterTitle(_ filter: SidebarFilter) -> String {
        switch filter {
        case .all: "All Todos"
        case .project(let project): project.name
        case .completed: "Completed"
        case .trash: "Trash"
        }
    }
}

// MARK: - Log Panel

private struct LogPanelView: View {
    let logService: LogService

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logService.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .foregroundStyle(.secondary)
                                Text(entry.level.rawValue)
                                    .foregroundStyle(entry.level == .error ? .red : .blue)
                                    .frame(width: 40, alignment: .leading)
                                Text(entry.message)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: logService.entries.count) { _, _ in
                    if let last = logService.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(height: 150)
        .background(.background)
    }
}
