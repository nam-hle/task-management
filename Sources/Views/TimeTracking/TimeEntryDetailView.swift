import SwiftUI
import SwiftData

struct TimeEntryDetailView: View {
    let entry: TimeEntry
    let onSave: (TimeEntryChanges) -> Void
    let onSplit: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Todo.title) private var todos: [Todo]

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String
    @State private var selectedTodoID: PersistentIdentifier?
    @State private var showSplitPicker = false
    @State private var splitTime: Date

    init(
        entry: TimeEntry,
        onSave: @escaping (TimeEntryChanges) -> Void,
        onSplit: @escaping (Date) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onSplit = onSplit
        _startTime = State(initialValue: entry.startTime)
        _endTime = State(initialValue: entry.endTime ?? Date())
        _notes = State(initialValue: entry.notes)
        _selectedTodoID = State(initialValue: entry.todo?.persistentModelID)
        _splitTime = State(initialValue: entry.startTime.addingTimeInterval(
            (entry.endTime ?? Date()).timeIntervalSince(entry.startTime) / 2
        ))
    }

    private var computedDuration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Form {
                Section("Time") {
                    DatePicker("Start", selection: $startTime)
                    DatePicker("End", selection: $endTime)
                    LabeledContent("Duration") {
                        Text(computedDuration.hoursMinutesSeconds)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("Details") {
                    LabeledContent("Source") {
                        Text(entry.source.label)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }

                    Picker("Todo", selection: $selectedTodoID) {
                        Text("None").tag(nil as PersistentIdentifier?)
                        ForEach(todos.filter(\.isActive)) { todo in
                            Text(todo.title)
                                .tag(todo.persistentModelID as PersistentIdentifier?)
                        }
                    }

                    LabeledContent("Status") {
                        Text(entry.bookingStatus.label)
                    }

                    if let appName = entry.applicationName {
                        LabeledContent("Application") {
                            Text(appName)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    Button {
                        showSplitPicker.toggle()
                    } label: {
                        Label("Split Entry", systemImage: "scissors")
                    }

                    if showSplitPicker {
                        DatePicker(
                            "Split at",
                            selection: $splitTime,
                            in: startTime...endTime
                        )

                        Button("Confirm Split") {
                            onSplit(splitTime)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Text("Edit Entry")
                .font(.headline)

            Spacer()

            Button("Save") {
                var changes = TimeEntryChanges()
                if startTime != entry.startTime { changes.startTime = startTime }
                if endTime != entry.endTime { changes.endTime = endTime }
                if notes != entry.notes { changes.notes = notes }
                if selectedTodoID != entry.todo?.persistentModelID {
                    if let todoID = selectedTodoID {
                        changes.todoID = todoID
                    } else {
                        changes.removeTodo = true
                    }
                }
                onSave(changes)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

}
