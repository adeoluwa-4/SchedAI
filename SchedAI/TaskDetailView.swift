import SwiftUI

/// Detail editor for a single task.
/// (Even if you don’t use it right now, it must compile.)
struct TaskDetailView: View {
    @EnvironmentObject private var app: AppState
    @State private var draft: TaskItem
    @State private var isPinned: Bool

    init(task: TaskItem) {
        _draft = State(initialValue: task)
        _isPinned = State(initialValue: task.isPinned)
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Task title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Details") {
                Picker("Priority", selection: $draft.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }

                Stepper(value: $draft.estimatedMinutes, in: 5...480, step: 5) {
                    HStack {
                        Text("Estimate")
                        Spacer()
                        Text("\(draft.estimatedMinutes)m").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Schedule") {
                Toggle("Pin start time", isOn: $isPinned)
                    .onChange(of: isPinned) { _, newValue in
                        draft.isPinned = newValue
                        if newValue {
                            // If pinning and no start exists, pick a sensible slot inside the work window.
                            if draft.scheduledStart == nil {
                                let start = suggestedPinnedStart()
                                draft.scheduledStart = start
                                draft.targetDay = Calendar.current.startOfDay(for: start)
                                draft.scheduledEnd = start.addingTimeInterval(TimeInterval(max(5, draft.estimatedMinutes) * 60))
                            }
                        } else {
                            // Unpin: clear schedule
                            draft.scheduledStart = nil
                            draft.scheduledEnd = nil
                        }
                    }

                if isPinned {
                    DatePicker(
                        "Start",
                        selection: Binding(
                            get: { draft.scheduledStart ?? Date() },
                            set: { newStart in
                                draft.isPinned = true
                                draft.scheduledStart = newStart
                                draft.targetDay = Calendar.current.startOfDay(for: newStart)
                                draft.scheduledEnd = newStart.addingTimeInterval(TimeInterval(max(5, draft.estimatedMinutes) * 60))
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                }
            }

            Section {
                Toggle("Completed", isOn: $draft.isCompleted)
                    .onChange(of: draft.isCompleted) { _, completed in
                        if completed {
                            // If completed, no need to keep reminders/schedule.
                            draft.isPinned = false
                            draft.scheduledStart = nil
                            draft.scheduledEnd = nil
                        }
                    }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Normalize title
            draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !draft.title.isEmpty {
                app.updateTask(draft)
            }
        }
    }

    private func roundedToNext15(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = comps.minute else { return date }
        let remainder = minute % 15
        let add = remainder == 0 ? 15 : (15 - remainder)
        return cal.date(byAdding: .minute, value: add, to: date) ?? date
    }

    private func suggestedPinnedStart() -> Date {
        let cal = Calendar.current
        let now = roundedToNext15(Date())

        func combineToday(_ time: Date) -> Date {
            let dayComps = cal.dateComponents([.year, .month, .day], from: now)
            let timeComps = cal.dateComponents([.hour, .minute, .second], from: time)
            var merged = DateComponents()
            merged.year = dayComps.year
            merged.month = dayComps.month
            merged.day = dayComps.day
            merged.hour = timeComps.hour
            merged.minute = timeComps.minute
            merged.second = 0
            return cal.date(from: merged) ?? now
        }

        let windowStart = combineToday(app.workStart)
        let windowEnd = combineToday(app.workEnd)

        if now < windowStart { return windowStart }
        if now >= windowEnd { return windowStart }
        return now
    }
}
