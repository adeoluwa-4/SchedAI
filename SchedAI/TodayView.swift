import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The Today screen: one clear timeline for the day.
///
/// Layout, top to bottom:
/// 1. Date, title and one summary line (tasks · planned time · done).
/// 2. A single focus card: what you should be doing now, or what's next.
/// 3. The timeline: every task once, with free gaps shown between them.
/// 4. Tasks that are not placed yet, with one button to fit them in.
struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var semester: SemesterStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showAI = false
    @State private var showQuickAdd = false
    @State private var quickAddNavigationTitle = "Quick Add"
    @State private var autoStartOfflineNLPFromWidget = false
    @State private var showCalendar = false
    @State private var showWorkWindowPicker = false
    @State private var planMessage: String? = nil
    @State private var planMessageHideWorkItem: DispatchWorkItem? = nil
    @State private var taskPendingSkip: TaskItem? = nil
    @State private var editingTask: TaskItem? = nil

    // MARK: - Derived data

    private let cal = Calendar.current

    private var planningDay: Date { cal.startOfDay(for: app.planningDate) }

    private var isPlanningToday: Bool { cal.isDate(planningDay, inSameDayAs: Date()) }

    private func appliesToPlanningDay(_ task: TaskItem) -> Bool {
        if let start = task.scheduledStart { return cal.isDate(start, inSameDayAs: planningDay) }
        if let target = task.targetDay { return cal.isDate(target, inSameDayAs: planningDay) }
        return true
    }

    /// Open tasks the scheduler may place on this day.
    private var activeTasks: [TaskItem] {
        app.tasks.filter { !$0.isCompleted && appliesToPlanningDay($0) && $0.canAutoSchedule(on: planningDay) }
    }

    private var completedTasks: [TaskItem] {
        app.tasks.filter { $0.isCompleted && appliesToPlanningDay($0) }
    }

    /// Everything with a time today, open or done, in time order. Shown once.
    private var timeline: [TaskItem] {
        app.tasks
            .filter { task in
                guard let start = task.scheduledStart, task.scheduledEnd != nil,
                      cal.isDate(start, inSameDayAs: planningDay) else { return false }
                return task.isCompleted || task.canAutoSchedule(on: planningDay)
            }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }

    private var openTimeline: [TaskItem] { timeline.filter { !$0.isCompleted } }

    /// Class meetings on the planning day, shown in the timeline as fixed blocks.
    private var classesToday: [(meeting: ClassMeeting, interval: DateInterval)] {
        semester.classes(on: planningDay)
    }

    private var unplacedTasks: [TaskItem] {
        activeTasks
            .filter { $0.scheduledStart == nil }
            .sorted { Scheduler.placementOrder($0, $1, planningDay: planningDay) }
    }

    private var missedPreviousTasks: [TaskItem] {
        guard isPlanningToday else { return [] }
        return app.tasks
            .filter { $0.canAutoSchedule(on: planningDay) }
            .filter { task in
                guard let end = task.scheduledEnd else { return false }
                return end < planningDay
            }
            .sorted { ($0.scheduledEnd ?? .distantPast) < ($1.scheduledEnd ?? .distantPast) }
    }

    private var plannedMinutes: Int {
        openTimeline.reduce(0) { total, task in
            guard let s = task.scheduledStart, let e = task.scheduledEnd else { return total }
            return total + Int(e.timeIntervalSince(s) / 60)
        }
    }

    private var currentTask: TaskItem? {
        guard isPlanningToday else { return nil }
        let now = Date()
        return openTimeline.first { task in
            guard let s = task.scheduledStart, let e = task.scheduledEnd else { return false }
            return s <= now && now < e
        }
    }

    private var nextTask: TaskItem? {
        let reference = isPlanningToday ? Date() : planningDay
        return openTimeline.first { ($0.scheduledStart ?? .distantPast) > reference }
    }

    private var workWindowEnd: Date? {
        app.workWindowEnabled ? app.schedulingWindow(for: planningDay).end : nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !missedPreviousTasks.isEmpty {
                    needsReviewSection
                }

                if timeline.isEmpty && unplacedTasks.isEmpty {
                    emptyState
                } else {
                    StudyCoachCard(onResult: showToast)
                    focusCard
                    if !timeline.isEmpty || !classesToday.isEmpty { timelineSection }
                    if !unplacedTasks.isEmpty { unplacedSection }
                }

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showAI) {
            AIPlanSheet(autoStartRecording: autoStartOfflineNLPFromWidget)
                .environmentObject(app)
        }
        .sheet(isPresented: $showQuickAdd) {
            AIAddTasksSheet(navigationTitle: quickAddNavigationTitle)
                .environmentObject(app)
        }
        .sheet(isPresented: $showCalendar) {
            BigCalendarSheet().environmentObject(app)
        }
        .sheet(isPresented: $showWorkWindowPicker) {
            WorkWindowPicker(start: $app.workStart, end: $app.workEnd)
                .presentationDetents([.medium])
        }
        .sheet(item: $editingTask) { task in
            TaskEditView(task: task).environmentObject(app)
        }
        .onAppear {
            handleWidgetVoiceRequestIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-SchedAIOpenPlan") { showAI = true }
            #endif
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleWidgetVoiceRequestIfNeeded()
        }
        #endif
        .onChange(of: showAI) { _, newValue in
            if !newValue { autoStartOfflineNLPFromWidget = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotifications.widgetVoicePlannerRequested)) { _ in
            openPlanSheet(autoStartRecording: true)
        }
        .alert("Calendar", isPresented: Binding(
            get: { app.calendarSyncMessage != nil },
            set: { if !$0 { app.calendarSyncMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.calendarSyncMessage ?? "")
        }
        .alert("Skip Today?", isPresented: Binding(
            get: { taskPendingSkip != nil },
            set: { if !$0 { taskPendingSkip = nil } }
        )) {
            Button("Skip Today", role: .destructive) {
                guard let task = taskPendingSkip else { return }
                withAnimation(.snappy) { app.skipTaskForToday(id: task.id, from: planningDay) }
                taskPendingSkip = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(skipTaskMessage)
        }
        .overlay(alignment: .bottom) {
            if let planMessage {
                toast(planMessage)
                    .padding(.bottom, 106)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(planningDay.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            HStack(alignment: .center, spacing: 10) {
                Text(isPlanningToday ? "Today" : planningDay.formatted(.dateTime.weekday(.wide)))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                iconButton("calendar", label: "Open calendar") { showCalendar = true }
                moreMenu
                Button {
                    Haptics.medium()
                    openPlanSheet(autoStartRecording: false)
                } label: {
                    Label("Plan", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan tasks")
            }

            if let summary = summaryLine {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .tint(.green)
                    .animation(.snappy, value: progress)
            }
        }
    }

    private var summaryLine: String? {
        let open = activeTasks.count
        let done = completedTasks.count
        guard open + done > 0 else { return nil }
        var parts = ["\(open) to do"]
        if plannedMinutes > 0 { parts.append("\(Self.duration(plannedMinutes)) planned") }
        parts.append("\(done) done")
        return parts.joined(separator: " · ")
    }

    private var progress: Double {
        let done = completedTasks.count
        let total = done + activeTasks.count
        return total == 0 ? 0 : Double(done) / Double(total)
    }

    private var moreMenu: some View {
        Menu {
            Button { replanDay() } label: { Label("Re-plan whole day", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(activeTasks.isEmpty)
            Button { openQuickAdd(title: "Quick Add") } label: { Label("Quick add", systemImage: "plus") }
            Button { showWorkWindowPicker = true } label: { Label("Work hours", systemImage: "clock") }
        } label: {
            circleIcon("ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func iconButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            circleIcon(name)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    // MARK: - Focus card (Now / Next)

    @ViewBuilder
    private var focusCard: some View {
        if let task = currentTask {
            FocusCard(
                eyebrow: "NOW · \(Self.minutesLeft(until: task.scheduledEnd))",
                title: task.title,
                detail: Self.timeRange(task),
                actionTitle: "Done",
                action: { complete(task) }
            )
        } else if let task = nextTask {
            FocusCard(
                eyebrow: isPlanningToday ? "UP NEXT · \(Self.startsIn(task.scheduledStart))" : "FIRST UP",
                title: task.title,
                detail: Self.timeRange(task),
                actionTitle: nil,
                action: nil
            )
        } else if !openTimeline.isEmpty || !unplacedTasks.isEmpty {
            FocusCard(
                eyebrow: "NOTHING SCHEDULED RIGHT NOW",
                title: unplacedTasks.isEmpty ? "You're clear for now" : "\(unplacedTasks.count) task\(unplacedTasks.count == 1 ? "" : "s") still need a time",
                detail: unplacedTasks.isEmpty ? "Enjoy the gap." : "Tap below to fit them into your day.",
                actionTitle: nil,
                action: nil
            )
        } else {
            FocusCard(
                eyebrow: "ALL DONE",
                title: "Everything for today is finished",
                detail: "\(completedTasks.count) task\(completedTasks.count == 1 ? "" : "s") completed.",
                actionTitle: nil,
                action: nil
            )
        }
    }

    // MARK: - Timeline

    private enum TimelineEntry: Identifiable {
        case task(TaskItem)
        case classMeeting(ClassMeeting, DateInterval)
        case gap(start: Date, minutes: Int)
        case afterHours

        var start: Date? {
            switch self {
            case .task(let t): return t.scheduledStart
            case .classMeeting(_, let i): return i.start
            default: return nil
            }
        }

        var end: Date? {
            switch self {
            case .task(let t): return t.scheduledEnd
            case .classMeeting(_, let i): return i.end
            default: return nil
            }
        }

        var id: String {
            switch self {
            case .task(let t): return t.id.uuidString
            case .classMeeting(let m, let i): return "class-\(m.id)-\(i.start.timeIntervalSince1970)"
            case .gap(let start, _): return "gap-\(start.timeIntervalSince1970)"
            case .afterHours: return "after-hours"
            }
        }
    }

    /// Tasks in order, with free gaps of 30+ minutes and an "after work hours"
    /// marker inserted between them.
    private var timelineEntries: [TimelineEntry] {
        let items: [TimelineEntry] = (timeline.map { .task($0) } + classesToday.map { .classMeeting($0.meeting, $0.interval) })
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }

        var entries: [TimelineEntry] = []
        var previousEnd: Date?
        var insertedAfterHours = false
        for item in items {
            guard let start = item.start else { continue }
            let isDone: Bool = { if case .task(let t) = item { return t.isCompleted }; return false }()
            if let end = workWindowEnd, !insertedAfterHours, start >= end, !entries.isEmpty {
                entries.append(.afterHours)
                insertedAfterHours = true
            } else if let previousEnd, !isDone {
                // Only show free time that is still ahead; a gap that ended an hour ago is noise.
                let gapStart = isPlanningToday ? max(previousEnd, Date()) : previousEnd
                let gap = Int(start.timeIntervalSince(gapStart) / 60)
                if gap >= 30 { entries.append(.gap(start: gapStart, minutes: gap)) }
            }
            entries.append(item)
            if let end = item.end { previousEnd = max(previousEnd ?? end, end) }
        }
        return entries
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Schedule")
            VStack(spacing: 0) {
                ForEach(timelineEntries) { entry in
                    switch entry {
                    case .task(let task):
                        TimelineTaskRow(
                            task: task,
                            isNow: task.id == currentTask?.id,
                            onToggle: { complete(task) },
                            onOpen: { editingTask = task }
                        )
                        .contextMenu { rowMenu(for: task) }
                    case .classMeeting(let meeting, let interval):
                        TimelineClassRow(meeting: meeting, interval: interval)
                    case .gap(let start, let minutes):
                        TimelineGapRow(start: start, minutes: minutes)
                    case .afterHours:
                        TimelineDividerRow(title: "After work hours")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for task: TaskItem) -> some View {
        Button { complete(task) } label: {
            Label(task.isCompleted ? "Mark not done" : "Mark done", systemImage: "checkmark.circle")
        }
        if !task.isCompleted {
            Button { withAnimation(.snappy) { app.rescheduleTaskForLater(id: task.id, from: planningDay) } } label: {
                Label("Move later today", systemImage: "arrow.clockwise")
            }
            Button { taskPendingSkip = task } label: {
                Label("Skip today", systemImage: "forward.end")
            }
        }
        Button { editingTask = task } label: { Label("Edit", systemImage: "pencil") }
    }

    // MARK: - Unplaced

    private var unplacedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Not placed yet")
            VStack(spacing: 0) {
                ForEach(Array(unplacedTasks.enumerated()), id: \.element.id) { index, task in
                    UnplacedRow(task: task, onOpen: { editingTask = task })
                    if index < unplacedTasks.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground)))

            Button { fitUnplaced() } label: {
                Label("Fit into my day", systemImage: "wand.and.stars")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
    }

    // MARK: - Needs review

    private var needsReviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("From earlier · needs a decision")
            ForEach(missedPreviousTasks) { task in
                MissedTaskCard(
                    task: task,
                    onDone: { complete(task) },
                    onReschedule: { withAnimation(.snappy) { app.rescheduleTaskForLater(id: task.id, from: planningDay) } },
                    onSkip: { taskPendingSkip = task }
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)
            VStack(spacing: 6) {
                Text("What's on your plate?")
                    .font(.title2.weight(.bold))
                Text("Type or say everything at once. SchedAI turns it into a timed plan, privately on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.medium()
                openPlanSheet(autoStartRecording: false)
            } label: {
                Label("Plan my day", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            Button("Speak instead") {
                Haptics.medium()
                openPlanSheet(autoStartRecording: true)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(.regularMaterial))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var skipTaskMessage: String {
        let title = taskPendingSkip?.title ?? "this task"
        if app.calendarSyncEnabled {
            return "This removes \"\(title)\" from today's plan and your synced calendar, but keeps the task."
        }
        return "This removes \"\(title)\" from today's plan, but keeps the task."
    }

    // MARK: - Actions

    private func complete(_ task: TaskItem) {
        Haptics.light()
        withAnimation(.snappy) { app.toggleComplete(id: task.id) }
    }

    private func fitUnplaced() {
        Haptics.medium()
        withAnimation(.snappy) { app.planUnscheduledOnly(for: planningDay) }
        reportPlanResult(success: "Added to your schedule.")
    }

    private func replanDay() {
        guard !activeTasks.isEmpty else { return }
        Haptics.medium()
        withAnimation(.snappy) { app.planToday(for: planningDay) }
        reportPlanResult(success: isPlanningToday ? "Today has been re-planned." : "Plan updated.")
    }

    private func reportPlanResult(success: String) {
        let overflow = app.lastPlanOverflow
        if overflow > 0 {
            showToast("\(overflow) task\(overflow == 1 ? "" : "s") didn't fit. Try shorter times or another day.")
        } else {
            showToast(success)
        }
    }

    private func showToast(_ message: String) {
        planMessageHideWorkItem?.cancel()
        withAnimation(.snappy) { planMessage = message }
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.2)) { planMessage = nil } }
        planMessageHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    private func openPlanSheet(autoStartRecording: Bool) {
        autoStartOfflineNLPFromWidget = autoStartRecording
        showAI = true
    }

    private func openQuickAdd(title: String) {
        quickAddNavigationTitle = title
        showQuickAdd = true
    }

    private func handleWidgetVoiceRequestIfNeeded() {
        guard app.consumeWidgetVoiceRequest() else { return }
        openPlanSheet(autoStartRecording: false)
    }

    // MARK: - Formatting

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func timeRange(_ task: TaskItem) -> String {
        guard let s = task.scheduledStart, let e = task.scheduledEnd else { return "" }
        return "\(s.formatted(date: .omitted, time: .shortened)) – \(e.formatted(date: .omitted, time: .shortened))"
    }

    static func minutesLeft(until end: Date?) -> String {
        guard let end else { return "in progress" }
        let minutes = max(1, Int(end.timeIntervalSinceNow / 60))
        return "\(duration(minutes)) left"
    }

    static func startsIn(_ start: Date?) -> String {
        guard let start else { return "" }
        let minutes = Int(start.timeIntervalSinceNow / 60)
        if minutes < 60 { return "in \(max(1, minutes)) min" }
        return "at \(start.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Components

private struct FocusCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.8))
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Time column, a rail with a dot, and the task card.
private struct TimelineTaskRow: View {
    let task: TaskItem
    let isNow: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    private var start: Date { task.scheduledStart ?? Date() }
    private var minutes: Int {
        guard let s = task.scheduledStart, let e = task.scheduledEnd else { return task.estimatedMinutes }
        return Int(e.timeIntervalSince(s) / 60)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(start.formatted(date: .omitted, time: .shortened))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(isNow ? Color.accentColor : .secondary)
                .frame(width: 64, alignment: .trailing)
                .padding(.top, 16)

            VStack(spacing: 0) {
                Circle()
                    .fill(task.isCompleted ? Color.green : (isNow ? Color.accentColor : Color(uiColor: .tertiaryLabel)))
                    .frame(width: 10, height: 10)
                    .padding(.top, 20)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 2)
            }
            .frame(width: 10)

            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.isCompleted ? Color.green : Color(uiColor: .tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Mark not done" : "Mark done")

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let course = task.course {
                            Text(course)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(CourseColor.color(for: course))
                        }
                        Text(TodayView.duration(minutes))
                        if task.priority == .high && !task.isCompleted {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.red)
                                .accessibilityLabel("Important")
                        }
                        if let due = task.deadline, !task.isCompleted, !task.isStudySession {
                            Label("Due \(due.formatted(date: .omitted, time: .shortened))", systemImage: "hourglass")
                                .foregroundStyle(.orange)
                        }
                        if task.isMissed() {
                            Text("Missed").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isNow ? Color.accentColor : .clear, lineWidth: 2)
                    )
            )
            .opacity(task.isCompleted ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .padding(.bottom, 8)
        }
    }
}

private struct TimelineGapRow: View {
    let start: Date
    let minutes: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear.frame(width: 64, height: 1)
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 2, height: 34)
                .frame(width: 10)
            Label("Free · \(TodayView.duration(minutes))", systemImage: "cup.and.saucer")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("\(TodayView.duration(minutes)) free")
    }
}

private struct TimelineDividerRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color(uiColor: .separator)).frame(height: 1)
        }
        .padding(.vertical, 10)
    }
}

private struct UnplacedRow: View {
    let task: TaskItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.priority(task.priority))
                    .frame(width: 8, height: 8)
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if let due = task.deadline {
                    Text("Due \(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(TodayView.duration(task.estimatedMinutes))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

private struct MissedTaskCard: View {
    let task: TaskItem
    let onDone: () -> Void
    let onReschedule: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.body.weight(.semibold))
                    if let start = task.scheduledStart {
                        Text("Was planned \(start.formatted(.dateTime.weekday(.wide).hour().minute()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Done", action: onDone).buttonStyle(.bordered).tint(.green)
                Button("Do today", action: onReschedule).buttonStyle(.bordered).tint(.accentColor)
                Button("Skip", action: onSkip).buttonStyle(.bordered).tint(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

/// A class meeting in the timeline: fixed, not checkable, course-colored.
private struct TimelineClassRow: View {
    let meeting: ClassMeeting
    let interval: DateInterval

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(interval.start.formatted(date: .omitted, time: .shortened))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .padding(.top, 14)

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(CourseColor.color(for: meeting.course))
                    .frame(width: 10, height: 10)
                    .padding(.top, 18)
                Rectangle().fill(Color(uiColor: .separator)).frame(width: 2)
            }
            .frame(width: 10)

            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(CourseColor.color(for: meeting.course))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.course).font(.body.weight(.semibold))
                    Text("Class · until \(interval.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CourseColor.color(for: meeting.course).opacity(0.10))
            )
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
    }
}
