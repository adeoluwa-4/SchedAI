import SwiftUI

struct BigCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var selectedDate: Date = Date()

    private var hasActiveTasks: Bool {
        app.tasks.contains { !$0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, 12)

                HStack {
                    Button {
                        selectedDate = Date()
                    } label: {
                        Label("Jump to Today", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Spacer()
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Planning for")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(longDate(selectedDate))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                List {
                    Section("Scheduled") {
                        let scheduled = app.tasks
                            .filter { !$0.isCompleted }
                            .filter {
                                guard let s = $0.scheduledStart else { return false }
                                return Calendar.current.isDate(s, inSameDayAs: selectedDate)
                            }
                            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }

                        if scheduled.isEmpty {
                            Text("No scheduled tasks on this day.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(scheduled) { t in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(t.title)
                                    HStack(spacing: 10) {
                                        if let s = t.scheduledStart, let e = t.scheduledEnd {
                                            Text("\(time(s))–\(time(e))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("\(t.estimatedMinutes)m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(t.priority.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedDate = app.planningDate
            }
            .onChange(of: selectedDate) { _, newValue in
                app.setPlanningDate(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        app.planToday(for: selectedDate)
                        dismiss()
                    } label: {
                        Label("Plan Day", systemImage: "wand.and.stars")
                    }
                    .disabled(!hasActiveTasks)
                }
            }
        }
    }

    private func time(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: d)
    }

    private func longDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d, yyyy"
        return df.string(from: d)
    }
}
