import SwiftUI
import SwiftData
import AppKit

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate = Date()
    @State private var exportResult: ExportResult?
    @State private var isGenerating = false
    @State private var showDuplicateWarning = false
    @State private var duplicateCount = 0
    @State private var exportRecordID: PersistentIdentifier?
    @State private var isCopied = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let result = exportResult {
                exportPreview(result)
            } else {
                emptyState
            }
        }
        .alert("Duplicate Entries", isPresented: $showDuplicateWarning) {
            Button("Export Anyway") { performExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(duplicateCount) entries have already been exported. Export again?")
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export")
                    .font(.headline)
                if let result = exportResult {
                    Text("\(result.entryIDs.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()

            Button {
                generateExport()
            } label: {
                Label("Generate", systemImage: "doc.text")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isGenerating)
        }
        .padding()
    }

    private func exportPreview(_ result: ExportResult) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(result.formattedText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()

            HStack(spacing: 12) {
                if isCopied {
                    Label("Copied!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                Spacer()

                Button {
                    copyToClipboard(result.formattedText)
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if exportRecordID == nil {
                    Button {
                        confirmExport(result)
                    } label: {
                        Label("Confirm Export", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button {
                        markBooked()
                    } label: {
                        Label("Mark as Booked", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Generate an export to preview")
                .foregroundStyle(.secondary)
            Text("Only reviewed entries will be included")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func generateExport() {
        isGenerating = true
        exportRecordID = nil
        isCopied = false
        let service = ExportService(modelContainer: modelContext.container)
        Task {
            do {
                let result = try await service.generateExport(for: selectedDate)
                let duplicates = try await service.checkDuplicates(
                    entryIDs: result.entryIDs
                )
                await MainActor.run {
                    exportResult = result
                    isGenerating = false
                    if !duplicates.isEmpty {
                        duplicateCount = duplicates.count
                        showDuplicateWarning = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performExport() {
        guard let result = exportResult else { return }
        confirmExport(result)
    }

    private func confirmExport(_ result: ExportResult) {
        let service = ExportService(modelContainer: modelContext.container)
        Task {
            do {
                let recordID = try await service.confirmExport(result: result)
                await MainActor.run {
                    exportRecordID = recordID
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func markBooked() {
        guard let recordID = exportRecordID else { return }
        let service = ExportService(modelContainer: modelContext.container)
        Task {
            do {
                try await service.markBooked(exportID: recordID)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isCopied = true
    }
}
