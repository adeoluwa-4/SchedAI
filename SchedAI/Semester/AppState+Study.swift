import Foundation

/// Study-session actions. Lives in the Semester folder so the student
/// features stay out of the already-large AppState.swift.
extension AppState {

    /// Creates spaced study sessions for new deadlines and adds them as tasks.
    @discardableResult
    func addStudySessions(for deadlines: [CourseDeadline], now: Date = Date()) -> Int {
        let sessions = StudyPlanner.sessions(for: deadlines, now: now)
        guard !sessions.isEmpty else { return 0 }
        addTasks(sessions)
        return sessions.count
    }

    /// Moves missed study sessions onto the remaining days before each
    /// deadline, then re-plans today so the change shows up immediately.
    func catchUpOnStudy(deadlines: [CourseDeadline], now: Date = Date()) -> StudyPlanner.CatchUpResult {
        let result = StudyPlanner.catchUp(tasks: tasks, deadlines: deadlines, now: now)
        guard result.moved > 0 else { return result }
        tasks = result.tasks
        planUnscheduledOnly(for: now)
        return result
    }

    func removeStudySessions(forDeadline id: UUID) {
        tasks.removeAll { $0.studyForDeadlineID == id && !$0.isCompleted }
    }

    /// Deadlines that have fallen behind, most urgent first.
    func studyBehind(deadlines: [CourseDeadline], now: Date = Date()) -> [StudyPlanner.Progress] {
        deadlines
            .map { StudyPlanner.progress(for: $0, tasks: tasks, now: now) }
            .filter { $0.behind > 0 && $0.daysLeft >= 0 && $0.deadline.due >= Calendar.current.startOfDay(for: now) }
            .sorted { $0.deadline.due < $1.deadline.due }
    }
}
