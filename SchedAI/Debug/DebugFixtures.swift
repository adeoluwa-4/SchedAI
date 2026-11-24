#if DEBUG
import Foundation

/// Sample data and screenshot helpers. Debug builds only; never shipped.
///
/// Launch arguments (Xcode: Product → Scheme → Edit Scheme → Run → Arguments):
/// - `-SchedAIDemoData`      a realistic single day of tasks
/// - `-SchedAIDemoSemester`  a student semester: classes, deadlines, study
///                           sessions (a few already missed)
/// - `-SchedAIOpenPlan`      opens the Plan sheet with sample text
/// - `-SchedAIOpenSyllabus`  opens syllabus import with a sample syllabus
/// - `-SchedAITab semester`  starts on the Semester tab
enum DebugFixtures {
    private static var applied = false

    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func applyLaunchArguments(app: AppState, semester: SemesterStore, now: Date = Date()) {
        guard !applied else { return }
        applied = true

        if has("-SchedAIDemoSemester") {
            let (tasks, deadlines, classes) = demoSemester(now: now)
            semester.replaceAll(deadlines: deadlines, classes: classes)
            app.tasks = tasks
            app.planUnscheduledOnly(for: now)
        } else if has("-SchedAIDemoData") {
            app.tasks = demoTasks(now: now)
        }
    }

    // MARK: - Sample day

    static func demoTasks(now: Date) -> [TaskItem] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ minutesFromNow: Int) -> Date {
            let rounded = cal.date(bySetting: .second, value: 0, of: now) ?? now
            let base = cal.date(byAdding: .minute, value: -(cal.component(.minute, from: rounded) % 15), to: rounded) ?? rounded
            return cal.date(byAdding: .minute, value: minutesFromNow, to: base) ?? base
        }
        func timed(_ title: String, _ offset: Int, _ minutes: Int, _ priority: TaskPriority = .medium,
                   done: Bool = false, pinned: Bool = false, deadline: Date? = nil) -> TaskItem {
            let start = at(offset)
            return TaskItem(title: title, estimatedMinutes: minutes, priority: priority,
                            isCompleted: done, completedAt: done ? now : nil, isPinned: pinned,
                            targetDay: day, scheduledStart: start,
                            scheduledEnd: cal.date(byAdding: .minute, value: minutes, to: start),
                            deadline: deadline)
        }
        return [
            timed("Morning run", -150, 30, .low, done: true),
            timed("Reply to recruiter emails", -105, 30, done: true),
            timed("Finish stats homework", -30, 60, .high, deadline: at(120)),
            timed("Team standup", 45, 15, pinned: true),
            timed("Prep pitch deck notes", 120, 45, .high),
            timed("Gym", 300, 60, .low, pinned: true),
            TaskItem(title: "Call Dad", estimatedMinutes: 20, priority: .medium, targetDay: day),
            TaskItem(title: "Grocery run", estimatedMinutes: 40, priority: .low, targetDay: day),
            TaskItem(title: "Scholarship form", estimatedMinutes: 30, priority: .medium, targetDay: day,
                     deadline: cal.date(byAdding: .day, value: 1, to: day.addingTimeInterval(17 * 3600)))
        ]
    }

    // MARK: - Sample semester

    static let sampleSyllabus = """
    CHEM 101: General Chemistry I — Fall 2026
    Lecture: MWF 10:00-10:50 AM, Hammond Hall 120
    Lab section: Thursdays 2:00-4:50 PM

    Schedule
    Week 13 (Nov 24): Chapter 9 reading — Thermochemistry
    Problem Set 7 due Nov 25
    Quiz 4 on Friday, Nov 27
    Week 14 (Dec 1): Lab report 5 due Dec 3 at 11:59 PM
    Midterm 2 — December 4
    Dec 8: Review session (optional)
    Final Exam: December 15, 8:00 AM
    """

    static func demoSemester(now: Date) -> (tasks: [TaskItem], deadlines: [CourseDeadline], classes: [ClassMeeting]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }

        let deadlines = [
            CourseDeadline(course: "CHEM 101", title: "Problem Set 7", kind: .assignment, due: day(2)),
            CourseDeadline(course: "PSYC 210", title: "Quiz 4", kind: .quiz, due: day(3, 13, 0), hasTime: true),
            CourseDeadline(course: "CHEM 101", title: "Midterm 2", kind: .exam, due: day(6, 10, 0), hasTime: true),
            CourseDeadline(course: "PSYC 210", title: "Research paper", kind: .paper, due: day(9)),
            CourseDeadline(course: "CHEM 101", title: "Final Exam", kind: .final, due: day(24, 8, 0), hasTime: true)
        ]
        let classes = [
            ClassMeeting(course: "CHEM 101", weekdays: [2, 4, 6], startMinutes: 10 * 60, endMinutes: 10 * 60 + 50),
            ClassMeeting(course: "PSYC 210", weekdays: [3, 5], startMinutes: 13 * 60, endMinutes: 14 * 60 + 15)
        ]

        var tasks = StudyPlanner.sessions(for: deadlines, now: now)
        // Pretend the syllabus was added last week: the first Midterm and paper
        // sessions were planned for earlier days and skipped, and one paper
        // session was done. Gives the catch-up coach something to fix.
        func reschedule(_ course: String, _ prefix: String, toDay offset: Int, done: Bool = false) {
            guard let i = tasks.firstIndex(where: { $0.course == course && $0.title.contains(prefix) && !$0.isCompleted }) else { return }
            tasks[i].targetDay = cal.date(byAdding: .day, value: offset, to: today)
            if done { tasks[i].isCompleted = true; tasks[i].completedAt = now }
        }
        reschedule("CHEM 101", "Midterm 2", toDay: -2)
        reschedule("PSYC 210", "Research paper", toDay: -3, done: true)
        reschedule("PSYC 210", "Research paper", toDay: -1)
        tasks += [
            TaskItem(title: "Email Prof. Lee about lab makeup", estimatedMinutes: 15, priority: .medium, targetDay: today),
            TaskItem(title: "Laundry", estimatedMinutes: 45, priority: .low, targetDay: today)
        ]
        return (tasks, deadlines, classes)
    }
}
#endif
