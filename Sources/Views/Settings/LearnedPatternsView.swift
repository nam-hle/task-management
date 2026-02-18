import SwiftUI
import SwiftData

struct LearnedPatternsView: View {
    @Query(sort: \LearnedPattern.lastConfirmedAt, order: .reverse)
    private var patterns: [LearnedPattern]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var serviceContainer

    @State private var errorMessage: String?

    var body: some View {
        Group {
            if patterns.isEmpty {
                emptyState
            } else {
                patternList
            }
        }
        .alert(
            "Error",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var patternList: some View {
        List {
            ForEach(patterns) { pattern in
                patternRow(pattern)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func patternRow(_ pattern: LearnedPattern) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pattern.contextType)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())

                    Text(pattern.identifierValue)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let todo = pattern.linkedTodo {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(todo.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)

                    if todo.isCompleted || todo.isTrashed {
                        Label("Stale — linked todo is inactive", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    Text("Confirmed \(pattern.confirmationCount)x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Last: \(pattern.lastConfirmedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !pattern.isActive {
                Text("Revoked")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                revokePattern(pattern)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(!pattern.isActive)
            .help("Revoke pattern")
        }
        .padding(.vertical, 4)
        .opacity(pattern.isActive ? 1.0 : 0.5)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No learned patterns yet")
                .foregroundStyle(.secondary)
            Text("Patterns are created when you review entries linked to todos")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func revokePattern(_ pattern: LearnedPattern) {
        let patternID = pattern.persistentModelID
        let service = serviceContainer!.makeLearnedPatternService()
        Task {
            do {
                try await service.revoke(patternID: patternID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
