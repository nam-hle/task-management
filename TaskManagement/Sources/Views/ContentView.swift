import SwiftUI
import SwiftData

enum NavigationItem: Hashable {
    case todos(SidebarFilter)
    case timeTracking
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sidebarSelection: NavigationItem? = .todos(.all)
    @State private var selectedTodo: Todo?

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
        .frame(minWidth: 800, minHeight: 500)
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
