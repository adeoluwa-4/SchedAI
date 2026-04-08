import SwiftUI

struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    let item: TaskItem

    @State private var title: String
    @State private var priority: TaskPriority
    @State private var estimatedMinutes: Int

    init(task: TaskItem) {
        self.item = task
        _title = State(initialValue: task.title)
        _priority = State(initialValue: task.priority)
        _estimatedMinutes = State(initialValue: task.estimatedMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Task title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    Stepper(value: $estimatedMinutes, in: 5...480, step: 5) {
                        HStack {
                            Text("Estimate")
                            Spacer()
                            Text("\(estimatedMinutes)m").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveAndDismiss() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = item
        updated.title = trimmed
        updated.priority = priority
        updated.estimatedMinutes = max(5, estimatedMinutes)

        app.updateTask(updated)
        dismiss()
    }
}
