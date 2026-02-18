import SwiftUI

struct TodoRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var serviceContainer
    let todo: Todo

    private var todoService: any TodoServiceProtocol {
        serviceContainer!.makeTodoService(context: modelContext)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                todoService.toggleComplete(todo)
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(todo.title)
                        .lineLimit(1)
                        .strikethrough(todo.isCompleted)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)

                    priorityBadge
                }

                HStack(spacing: 6) {
                    if let project = todo.project {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: project.color) ?? .blue)
                                .frame(width: 6, height: 6)
                            Text(project.name)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    ForEach(todo.tags) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(hex: tag.color)?.opacity(0.2) ?? .gray.opacity(0.2),
                                        in: Capsule())
                            .foregroundStyle(Color(hex: tag.color) ?? .gray)
                    }

                    if let dueDate = todo.dueDate {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            Text(dueDate, style: .date)
                        }
                        .font(.caption)
                        .foregroundStyle(dueDate < Date() && !todo.isCompleted ? .red : .secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var priorityBadge: some View {
        switch todo.priority {
        case .high:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .low:
            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .medium:
            EmptyView()
        }
    }
}
