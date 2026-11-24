import SwiftUI

/// The Semester tab: every upcoming deadline with study progress, the
/// catch-up coach, and class times.
struct SemesterView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var semester: SemesterStore

    @State private var showImport = false
    @State private var editingClass: ClassMeeting?
    @State private var toast: String?
    @State private var toastHide: DispatchWorkItem?
    @State private var pendingDelete: CourseDeadline?

    private var upcoming: [CourseDeadline] { semester.upcomingDeadlines() }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if semester.deadlines.isEmpty && semester.classes.isEmpty {
                    emptyState
                } else {
                    StudyCoachCard(onResult: showToast)
                    if !upcoming.isEmpty { deadlinesSection }
                    classesSection
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showImport) {
            SyllabusImportSheet(onFinish: showToast)
                .environmentObject(app)
                .environmentObject(semester)
        }
        .sheet(item: $editingClass) { meeting in
            ClassEditorSheet(meeting: meeting, isNew: !semester.classes.contains { $0.id == meeting.id })
                .environmentObject(semester)
                .presentationDetents([.medium, .large])
        }
        .alert("Remove deadline?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Remove", role: .destructive) {
                guard let d = pendingDelete else { return }
                withAnimation(.snappy) {
                    app.removeStudySessions(forDeadline: d.id)
                    semester.removeDeadline(id: d.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(pendingDelete?.displayTitle ?? "it") and its unfinished study sessions.")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.bottom, 106).padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if DEBUG
        .onAppear { if DebugFixtures.has("-SchedAIOpenSyllabus") { showImport = true } }
        #endif
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(semesterSubtitle.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            HStack(alignment: .center) {
                Text("Semester")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Spacer()
                Button {
                    Haptics.medium()
                    showImport = true
                } label: {
                    Label("Syllabus", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a syllabus")
            }
        }
    }

    private var semesterSubtitle: String {
        let courses = semester.courses
        if courses.isEmpty { return "Your classes and deadlines" }
        return "\(courses.count) course\(courses.count == 1 ? "" : "s") · \(upcoming.count) deadline\(upcoming.count == 1 ? "" : "s") ahead"
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)
            VStack(spacing: 8) {
                Text("Drop in your syllabus")
                    .font(.title2.weight(.bold))
                Text("SchedAI finds every exam and deadline, blocks out your class times, and plans study sessions before each one. It all stays on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showImport = true
            } label: {
                Label("Add a syllabus", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            Text("PDF, photo, or pasted text")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    // MARK: Deadlines

    private var deadlinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming up").font(.title3.weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, deadline in
                    DeadlineRow(progress: StudyPlanner.progress(for: deadline, tasks: app.tasks))
                        .contextMenu {
                            Button(role: .destructive) { pendingDelete = deadline } label: {
                                Label("Remove deadline", systemImage: "trash")
                            }
                        }
                    if index < upcoming.count - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        }
    }

    // MARK: Classes

    private var classesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Classes").font(.title3.weight(.bold))
                Spacer()
                Button {
                    editingClass = ClassMeeting(course: semester.courses.first ?? "", weekdays: [2, 4, 6],
                                                startMinutes: 10 * 60, endMinutes: 10 * 60 + 50)
                } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
            }
            if semester.classes.isEmpty {
                Text("Add your class times and SchedAI will never plan study over them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(semester.classes.enumerated()), id: \.element.id) { index, meeting in
                        Button { editingClass = meeting } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(CourseColor.color(for: meeting.course))
                                    .frame(width: 6, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.course).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text("\(meeting.weekdaySummary) · \(meeting.timeSummary)")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < semester.classes.count - 1 { Divider().padding(.leading, 34) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground)))
            }
        }
    }

    private func showToast(_ message: String) {
        toastHide?.cancel()
        withAnimation(.snappy) { toast = message }
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.2)) { toast = nil } }
        toastHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

/// One deadline: course color, what it is, when, and study progress.
private struct DeadlineRow: View {
    let progress: StudyPlanner.Progress
    private var d: CourseDeadline { progress.deadline }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CourseColor.color(for: d.course).opacity(0.15))
                Image(systemName: d.kind.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CourseColor.color(for: d.course))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(d.title).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(d.course) · \(dueText)")
                    .font(.subheadline)
                    .foregroundStyle(progress.daysLeft <= 2 ? Color.orange : .secondary)
                    .lineLimit(1)
                if progress.total > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: progress.fraction)
                            .tint(progress.behind > 0 ? .orange : .green)
                            .frame(maxWidth: 110)
                        Text(sessionText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(progress.behind > 0 ? Color.orange : .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(countdown)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(progress.daysLeft <= 2 ? Color.orange : .primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var dueText: String {
        if d.hasTime {
            // "Nov 29, 10 AM" / "Nov 26, 1:30 PM": short enough to fit on one line.
            let onTheHour = Calendar.current.component(.minute, from: d.due) == 0
            return d.due.formatted(onTheHour
                ? .dateTime.month(.abbreviated).day().hour()
                : .dateTime.month(.abbreviated).day().hour().minute())
        }
        return d.due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var countdown: String {
        switch progress.daysLeft {
        case 0: return "Today"
        case 1: return "1 day"
        default: return "\(progress.daysLeft) days"
        }
    }

    private var sessionText: String {
        if progress.behind > 0 { return "\(progress.done)/\(progress.total) · \(progress.behind) missed" }
        return "\(progress.done)/\(progress.total) sessions"
    }
}

/// Add or edit a recurring class meeting.
struct ClassEditorSheet: View {
    @EnvironmentObject private var semester: SemesterStore
    @Environment(\.dismiss) private var dismiss
    @State var meeting: ClassMeeting
    let isNew: Bool

    private let dayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("e.g. CHEM 101", text: $meeting.course)
                        .textInputAutocapitalization(.characters)
                }
                Section("Days") {
                    HStack(spacing: 6) {
                        ForEach(dayOrder, id: \.self) { day in
                            let on = meeting.weekdays.contains(day)
                            Button {
                                if on { meeting.weekdays.remove(day) } else { meeting.weekdays.insert(day) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .foregroundStyle(on ? .white : .primary)
                                    .background(Circle().fill(on ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Time") {
                    DatePicker("Starts", selection: minutesBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: minutesBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                }
                if !isNew {
                    Section {
                        Button("Remove class", role: .destructive) {
                            semester.removeClass(id: meeting.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add class" : "Edit class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        semester.upsert(meeting)
                        dismiss()
                    }
                    .disabled(meeting.course.trimmingCharacters(in: .whitespaces).isEmpty
                              || meeting.weekdays.isEmpty || meeting.endMinutes <= meeting.startMinutes)
                }
            }
        }
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<ClassMeeting, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = meeting[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                meeting[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
