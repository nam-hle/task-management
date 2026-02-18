import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTodo: Todo?
    let filter: SidebarFilter
    @State private var searchText = ""
    @State private var isAddingTodo = false
    @State private var newTodoTitle = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            let todos = filteredTodos
            if todos.isEmpty {
                emptyState
            } else {
                List(selection: $selectedTodo) {
                    if isAddingTodo {
                        newTodoField
                    }

                    ForEach(todos) { todo in
                        TodoRow(todo: todo)
                            .tag(todo)
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingTodo = true
                } label: {
                    Label("Add Todo", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(filter == .trash || filter == .completed)
            }
        }
    }

    private var filteredTodos: [Todo] {
        let service = TodoService(context: modelContext)

        do {
            switch filter {
            case .all:
                return try service.list(
                    isCompleted: false, searchText: searchText
                )
            case .project(let project):
                return try service.list(
                    project: project, isCompleted: false, searchText: searchText
                )
            case .completed:
                return try service.list(
                    isCompleted: true, searchText: searchText
                )
            case .trash:
                if searchText.isEmpty {
                    return try service.listTrashed()
                }
                return try service.listTrashed().filter {
                    $0.title.localizedCaseInsensitiveContains(searchText)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            if isAddingTodo {
                List {
                    newTodoField
                }
                .listStyle(.inset)
            } else {
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
                if filter != .trash && filter != .completed {
                    Button("Create Todo") {
                        isAddingTodo = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var newTodoField: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("New todo title...", text: $newTodoTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    createTodo()
                }
                .onExitCommand {
                    isAddingTodo = false
                    newTodoTitle = ""
                }
        }
        .padding(.vertical, 4)
    }

    private var emptyStateIcon: String {
        switch filter {
        case .all: "checklist"
        case .project: "folder"
        case .completed: "checkmark.circle"
        case .trash: "trash"
        }
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty { return "No matching todos" }
        switch filter {
        case .all: return "No todos yet"
        case .project: return "No todos in this project"
        case .completed: return "No completed todos"
        case .trash: return "Trash is empty"
        }
    }

    private func createTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            isAddingTodo = false
            newTodoTitle = ""
            return
        }

        let service = TodoService(context: modelContext)
        var project: Project? = nil
        if case .project(let p) = filter {
            project = p
        }
        do {
            let todo = try service.create(title: title, project: project)
            selectedTodo = todo
        } catch {
            errorMessage = error.localizedDescription
        }
        isAddingTodo = false
        newTodoTitle = ""
    }
}
