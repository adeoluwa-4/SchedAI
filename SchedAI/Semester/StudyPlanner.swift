import Foundation

/// Plans study sessions backward from deadlines, and repairs the plan when
/// sessions are missed. Pure functions: no state, easy to test.
///
/// Sessions are created as day-assigned tasks (no clock time). The existing
/// deadline-aware `Scheduler` then fits them around classes and other tasks
/// when each day is planned.
enum StudyPlanner {

    // MARK: - Planning

    /// Spaced sessions for one deadline, ending the day before it is due.
    static func sessions(
        for deadline: CourseDeadline,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let plan = deadline.kind.studyPlan
        let days = studyDays(before: deadline.due, leadDays: plan.leadDays, sessions: plan.sessions, now: now, calendar: calendar)
        guard !days.isEmpty else { return [] }

        let total = days.count
        return days.enumerated().map { index, day in
            let numbering = total > 1 ? " (\(index + 1)/\(total))" : ""
            return TaskItem(
                title: "\(deadline.kind.sessionVerb) \(deadline.course) \(deadline.title)\(numbering)",
                estimatedMinutes: plan.minutes,
                priority: deadline.kind.priority,
                targetDay: day,
                deadline: deadline.due,
                course: deadline.course,
                studyForDeadlineID: deadline.id
            )
        }
    }

    static func sessions(for deadlines: [CourseDeadline], now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        deadlines.flatMap { sessions(for: $0, now: now, calendar: calendar) }
    }

    /// Picks up to `sessions` days between the start of the lead window (or
    /// today, if later) and the day before the deadline, spread evenly and
    /// weighted toward the deadline, the way spaced review works.
    static func studyDays(
        before due: Date,
        leadDays: Int,
        sessions: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        guard dueDay >= today else { return [] }

        // Study through the day before; if due today, today is all there is.
        let lastDay = dueDay > today ? (calendar.date(byAdding: .day, value: -1, to: dueDay) ?? today) : today
        let windowStart = max(today, calendar.date(byAdding: .day, value: -leadDays, to: dueDay) ?? today)
        guard windowStart <= lastDay else { return [today] }

        var available: [Date] = []
        var cursor = windowStart
        while cursor <= lastDay {
            available.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? lastDay.addingTimeInterval(86_400)
        }

        let count = min(sessions, available.count)
        guard count > 0 else { return [] }
        // Evenly spaced, anchored to the end: e.g. 3 sessions over 6 days → days 2, 4, 6.
        let picked = (1...count).map { i -> Date in
            let position = Int((Double(i) * Double(available.count) / Double(count)).rounded(.up)) - 1
            return available[max(0, min(available.count - 1, position))]
        }
        return Array(Set(picked)).sorted()
    }

    // MARK: - Progress

    struct Progress: Equatable {
        var deadline: CourseDeadline
        var done: Int
        var total: Int
        /// Sessions whose planned day has passed without being done.
        var behind: Int
        var daysLeft: Int

        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    static func progress(
        for deadline: CourseDeadline,
        tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Progress {
        let sessions = tasks.filter { $0.studyForDeadlineID == deadline.id }
        let today = calendar.startOfDay(for: now)
        let behind = sessions.filter { isMissed($0, today: today, now: now, calendar: calendar) }.count
        let daysLeft = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: deadline.due)).day ?? 0
        return Progress(
            deadline: deadline,
            done: sessions.filter(\.isCompleted).count,
            total: sessions.count,
            behind: behind,
            daysLeft: max(0, daysLeft)
        )
    }

    static func isMissed(_ task: TaskItem, today: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard task.isStudySession, !task.isCompleted else { return false }
        if let end = task.scheduledEnd { return end < now }
        if let day = task.targetDay { return calendar.startOfDay(for: day) < today }
        return false
    }

    // MARK: - Catch-up

    struct CatchUpResult {
        var tasks: [TaskItem]
        var moved: Int
        /// Missed sessions whose deadline has already passed; left untouched.
        var tooLate: Int
    }

    /// Moves every missed study session onto the remaining days before its
    /// deadline, filling the lightest days first so no single day gets crushed.
    static func catchUp(
        tasks: [TaskItem],
        deadlines: [CourseDeadline],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CatchUpResult {
        var updated = tasks
        let today = calendar.startOfDay(for: now)
        var moved = 0
        var tooLate = 0

        // Study minutes already planned per day, so we can find the lightest day.
        var load: [Date: Int] = [:]
        for t in updated where t.isStudySession && !t.isCompleted && !isMissed(t, today: today, now: now, calendar: calendar) {
            if let d = t.targetDay { load[calendar.startOfDay(for: d), default: 0] += t.estimatedMinutes }
        }

        let missedIndices = updated.indices
            .filter { isMissed(updated[$0], today: today, now: now, calendar: calendar) }
            .sorted { (updated[$0].deadline ?? .distantFuture) < (updated[$1].deadline ?? .distantFuture) }

        for i in missedIndices {
            guard let deadline = deadlines.first(where: { $0.id == updated[i].studyForDeadlineID }) else { continue }
            let dueDay = calendar.startOfDay(for: deadline.due)
            guard dueDay >= today else { tooLate += 1; continue }

            let lastDay = dueDay > today ? (calendar.date(byAdding: .day, value: -1, to: dueDay) ?? today) : today
            var candidates: [Date] = []
            var cursor = today
            while cursor <= lastDay {
                candidates.append(cursor)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? lastDay.addingTimeInterval(86_400)
            }
            // Lightest day wins; ties go to the earliest day.
            guard let target = candidates.min(by: { (load[$0] ?? 0, $0) < (load[$1] ?? 0, $1) }) else { continue }

            updated[i].targetDay = target
            updated[i].scheduledStart = nil
            updated[i].scheduledEnd = nil
            updated[i].isPinned = false
            updated[i].planState = .ready
            load[target, default: 0] += updated[i].estimatedMinutes
            moved += 1
        }
        return CatchUpResult(tasks: updated, moved: moved, tooLate: tooLate)
    }
}
