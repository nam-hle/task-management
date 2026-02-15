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

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgbValue) else { return nil }

        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
