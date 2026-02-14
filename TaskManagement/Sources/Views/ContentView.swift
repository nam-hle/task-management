import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sidebarSelection: SidebarFilter? = .all
    @State private var selectedTodo: Todo?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
        } content: {
            if let filter = sidebarSelection {
                TodoListView(selectedTodo: $selectedTodo, filter: filter)
                    .navigationTitle(filterTitle(filter))
            } else {
                Text("Select a filter")
                    .foregroundStyle(.secondary)
            }
        } detail: {
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
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: sidebarSelection) { _, _ in
            selectedTodo = nil
        }
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
