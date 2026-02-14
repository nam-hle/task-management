import SwiftUI
import SwiftData

enum SidebarFilter: Hashable {
    case all
    case project(Project)
    case completed
    case trash
}

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Binding var selection: SidebarFilter?
    @State private var isAddingProject = false
    @State private var newProjectName = ""

    var body: some View {
        List(selection: $selection) {
            Section("Filters") {
                Label("All Todos", systemImage: "tray.full")
                    .tag(SidebarFilter.all)

                Label("Completed", systemImage: "checkmark.circle")
                    .tag(SidebarFilter.completed)

                Label("Trash", systemImage: "trash")
                    .tag(SidebarFilter.trash)
            }

            Section("Projects") {
                ForEach(projects) { project in
                    ProjectRow(project: project)
                        .tag(SidebarFilter.project(project))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteProject(project)
                            }
                        }
                }

                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            createProject()
                        }
                        .onExitCommand {
                            isAddingProject = false
                            newProjectName = ""
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingProject = true
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationTitle("TaskManagement")
        .onAppear {
            if selection == nil {
                selection = .all
            }
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isAddingProject = false
            newProjectName = ""
            return
        }
        let service = ProjectService(context: modelContext)
        _ = service.create(name: name)
        isAddingProject = false
        newProjectName = ""
    }

    private func deleteProject(_ project: Project) {
        let service = ProjectService(context: modelContext)
        service.delete(project)
        if case .project(let selected) = selection, selected.id == project.id {
            selection = .all
        }
    }
}
