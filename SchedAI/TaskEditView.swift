import SwiftUI

struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    let item: TaskItem

    @State private var title: String
    @State private var priority: TaskPriority
    @State private var estimatedMinutes: Int
    @State private var hasScheduledTime: Bool
    @State private var scheduledStart: Date
    @State private var scheduledEnd: Date

    init(task: TaskItem) {
        self.item = task
        _title = State(initialValue: task.title)
        _priority = State(initialValue: task.priority)
        _estimatedMinutes = State(initialValue: task.estimatedMinutes)
        _hasScheduledTime = State(initialValue: task.scheduledStart != nil)
        let start = task.scheduledStart ?? Date()
        _scheduledStart = State(initialValue: start)
        _scheduledEnd = State(
            initialValue: task.scheduledEnd
                ?? Calendar.current.date(byAdding: .minute, value: max(5, task.estimatedMinutes), to: start)
                ?? start.addingTimeInterval(300)
        )
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

                Section("Schedule") {
                    Toggle(
                        "Set specific time",
                        isOn: Binding(
                            get: { hasScheduledTime },
                            set: { enabled in
                                hasScheduledTime = enabled
                                if enabled {
                                    if scheduledEnd <= scheduledStart {
                                        scheduledEnd = Calendar.current.date(
                                            byAdding: .minute,
                                            value: max(5, estimatedMinutes),
                                            to: scheduledStart
                                        ) ?? minimumEnd(for: scheduledStart)
                                    }
                                }
                            }
                        )
                    )

                    if hasScheduledTime {
                        DatePicker(
                            "Start",
                            selection: Binding(
                                get: { scheduledStart },
                                set: { newStart in
                                    let currentDuration = max(5, estimatedMinutes)
                                    scheduledStart = newStart
                                    scheduledEnd = Calendar.current.date(
                                        byAdding: .minute,
                                        value: currentDuration,
                                        to: newStart
                                    ) ?? minimumEnd(for: newStart)
                                }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { scheduledEnd },
                                set: { newEnd in
                                    let normalized = max(newEnd, minimumEnd(for: scheduledStart))
                                    scheduledEnd = normalized
                                    estimatedMinutes = durationMinutes(start: scheduledStart, end: normalized)
                                }
                            ),
                            in: minimumEnd(for: scheduledStart)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(estimatedMinutes)m")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onChange(of: estimatedMinutes) { _, newValue in
                guard hasScheduledTime else { return }
                let safe = max(5, newValue)
                scheduledEnd = Calendar.current.date(
                    byAdding: .minute,
                    value: safe,
                    to: scheduledStart
                ) ?? minimumEnd(for: scheduledStart)
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
        if hasScheduledTime {
            let normalizedEnd = max(scheduledEnd, minimumEnd(for: scheduledStart))
            let duration = durationMinutes(start: scheduledStart, end: normalizedEnd)
            updated.estimatedMinutes = duration
            updated.isPinned = true
            updated.targetDay = Calendar.current.startOfDay(for: scheduledStart)
            updated.scheduledStart = scheduledStart
            updated.scheduledEnd = normalizedEnd
        } else {
            updated.estimatedMinutes = max(5, estimatedMinutes)
            updated.isPinned = false
            updated.scheduledStart = nil
            updated.scheduledEnd = nil
        }

        app.updateTask(updated)
        dismiss()
    }

    private func minimumEnd(for start: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: start) ?? start.addingTimeInterval(300)
    }

    private func durationMinutes(start: Date, end: Date) -> Int {
        max(5, Int(end.timeIntervalSince(start) / 60))
    }
}
