import SwiftUI
import SwiftData

struct TodoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var serviceContainer
    @Bindable var todo: Todo
    @Query(sort: \Project.sortOrder) private var allProjects: [Project]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleSection
                metadataSection
                descriptionSection
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if todo.isTrashed {
                    Button {
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.restore(todo)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.toggleComplete(todo)
                    } label: {
                        Label(
                            todo.isCompleted ? "Reopen" : "Complete",
                            systemImage: todo.isCompleted ? "arrow.uturn.backward" : "checkmark"
                        )
                    }
                    .keyboardShortcut(.return, modifiers: .command)

                    Button {
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.softDelete(todo)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
    }

    @ViewBuilder
    private var titleSection: some View {
        if isEditingTitle {
            TextField("Title", text: $editedTitle)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .onSubmit {
                    commitTitleEdit()
                }
                .onExitCommand {
                    isEditingTitle = false
                }
        } else {
            Text(todo.title)
                .font(.title2.bold())
                .strikethrough(todo.isCompleted)
                .onTapGesture(count: 2) {
                    editedTitle = todo.title
                    isEditingTitle = true
                }
        }

        if todo.isCompleted, let completedAt = todo.completedAt {
            Label("Completed \(completedAt, style: .relative) ago", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }

        if todo.isTrashed, let deletedAt = todo.deletedAt {
            Label("Trashed \(deletedAt, style: .relative) ago", systemImage: "trash")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Priority
            HStack {
                Text("Priority")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: Binding(
                    get: { todo.priority },
                    set: { newValue in
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.update(todo, priority: newValue)
                    }
                )) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            // Project
            HStack {
                Text("Project")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: Binding(
                    get: { todo.project },
                    set: { newValue in
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.update(todo, project: newValue)
                    }
                )) {
                    Text("None").tag(Project?.none)
                    ForEach(allProjects) { project in
                        HStack {
                            Circle()
                                .fill(Color(hex: project.color) ?? .blue)
                                .frame(width: 8, height: 8)
                            Text(project.name)
                        }
                        .tag(Optional(project))
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            // Due Date
            HStack {
                Text("Due Date")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                if let dueDate = Binding(
                    get: { todo.dueDate },
                    set: { newValue in
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.update(todo, dueDate: newValue)
                    }
                ).wrappedValue {
                    DatePicker("", selection: Binding(
                        get: { dueDate },
                        set: { newValue in
                            let service = serviceContainer!.makeTodoService(context: modelContext)
                            service.update(todo, dueDate: newValue)
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()

                    Button {
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.update(todo, dueDate: Optional<Date>.none)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set Due Date") {
                        let service = serviceContainer!.makeTodoService(context: modelContext)
                        service.update(todo, dueDate: Calendar.current.date(
                            byAdding: .day, value: 1, to: Date()
                        ))
                    }
                }
            }

            // Tags
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags")
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(todo.tags) { tag in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: tag.color) ?? .gray)
                                .frame(width: 6, height: 6)
                            Text(tag.name)
                                .font(.caption)
                            Button {
                                todo.tags.removeAll { $0.id == tag.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }

                    Menu {
                        let unassigned = allTags.filter { tag in
                            !todo.tags.contains { $0.id == tag.id }
                        }
                        if unassigned.isEmpty {
                            Text("No more tags")
                        } else {
                            ForEach(unassigned) { tag in
                                Button(tag.name) {
                                    todo.tags.append(tag)
                                }
                            }
                        }
                    } label: {
                        Label("Add Tag", systemImage: "plus")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }

        Divider()
    }

    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.headline)

            TextEditor(text: Binding(
                get: { todo.descriptionText },
                set: { newValue in
                    todo.descriptionText = newValue
                    todo.updatedAt = Date()
                }
            ))
            .font(.body)
            .frame(minHeight: 120)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func commitTitleEdit() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let service = serviceContainer!.makeTodoService(context: modelContext)
            service.update(todo, title: trimmed)
        }
        isEditingTitle = false
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(
                x: bounds.minX + position.x,
                y: bounds.minY + position.y
            ), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
