import SwiftUI

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: project.color) ?? .blue)
                .frame(width: 10, height: 10)

            Text(project.name)
                .lineLimit(1)

            Spacer()

            let activeCount = project.todos.filter { $0.deletedAt == nil && !$0.isCompleted }.count
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
