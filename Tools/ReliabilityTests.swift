import Foundation

// swiftc TaskItem.swift Scheduler.swift NotificationManager.swift Tools/ReliabilityTests.swift
@main
struct ReliabilityTests {
    static func main() {
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2030, month: 5, day: 4))!
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        var saved = TaskItem(title: "Existing task", estimatedMinutes: 60, priority: .high)
        saved.scheduledStart = at(9)
        saved.scheduledEnd = at(10)
        saved.targetDay = day
        let snapshot = saved
        var draft = TaskItem(title: "New task", estimatedMinutes: 30, priority: .medium)
        draft.targetDay = day
        var planned = [draft]
        let busy = Scheduler.occupiedIntervals([saved])
        let overflow = Scheduler.planToday(tasks: &planned, workStart: at(9), workEnd: at(17),
                                           day: day, now: at(8), externalBusyIntervals: busy)
        precondition(overflow == 0 && planned[0].scheduledStart! >= at(10))
        precondition(saved == snapshot, "Preview must not move an existing task")
        precondition(!Scheduler.overlaps(planned[0], busy: busy))
        let preview = planned
        _ = Scheduler.planToday(tasks: &planned, workStart: at(9), workEnd: at(17),
                                day: day, now: at(8), externalBusyIntervals: busy)
        precondition(preview == planned, "Unchanged inputs must produce the same preview")

        planned = [draft]
        let full = Scheduler.planToday(tasks: &planned, workStart: at(9), workEnd: at(17), day: day,
                                       now: at(8), externalBusyIntervals: [DateInterval(start: at(9), end: at(17))])
        precondition(full == 1 && planned[0].scheduledStart == nil)
        var fixed = draft
        fixed.isPinned = true
        fixed.scheduledStart = at(9, 30)
        fixed.scheduledEnd = at(10)
        precondition(Scheduler.overlaps(fixed, busy: busy))
        fixed.scheduledStart = at(10)
        fixed.scheduledEnd = at(10, 30)
        precondition(!Scheduler.overlaps(fixed, busy: busy), "Touching boundaries are not conflicts")
        precondition(Scheduler.occupiedIntervals([saved], excluding: [saved.id]).isEmpty)
        saved.isCompleted = true
        precondition(Scheduler.occupiedIntervals([saved]).isEmpty)

        precondition(NotificationManager.reminderDate(start: at(10), minutesBefore: 10, now: at(9)) == at(9, 50))
        precondition(NotificationManager.reminderDate(start: at(10), minutesBefore: 10, now: at(9, 55)) == at(10))
        precondition(NotificationManager.reminderDate(start: at(10), minutesBefore: 0, now: at(9, 55)) == at(10))
        precondition(NotificationManager.reminderDate(start: at(10), minutesBefore: -10, now: at(9)) == at(10))
        precondition(NotificationManager.reminderDate(start: at(10), minutesBefore: 10, now: at(10)) == nil)
        precondition(NotificationManager.reminderDate(start: at(10), minutesBefore: 10, now: at(11)) == nil)
        var changedAvailability = preview
        _ = Scheduler.planToday(tasks: &changedAvailability, workStart: at(9), workEnd: at(17), day: day,
                                now: at(8), externalBusyIntervals: [DateInterval(start: at(9), end: at(12))])
        precondition(changedAvailability != preview, "Changed availability must produce a reviewable new preview")
        var pinnedConflict = fixed
        pinnedConflict.scheduledStart = at(9, 30)
        pinnedConflict.scheduledEnd = at(10)
        var pinnedPlan = [pinnedConflict]
        _ = Scheduler.planToday(tasks: &pinnedPlan, workStart: at(9), workEnd: at(17), day: day,
                                now: at(8), externalBusyIntervals: busy)
        precondition(pinnedPlan[0].scheduledStart == at(9, 30), "Warnings must not silently move fixed times")
        precondition(Scheduler.overlaps(pinnedPlan[0], busy: busy))
        var overnight = snapshot
        overnight.scheduledStart = day.addingTimeInterval(-3600)
        overnight.scheduledEnd = at(10)
        planned = [draft]
        _ = Scheduler.planToday(tasks: &planned, workStart: at(9), workEnd: at(17), day: day,
                                now: at(8), externalBusyIntervals: Scheduler.occupiedIntervals([overnight]))
        precondition(planned[0].scheduledStart! >= at(10), "A previous day's overnight task still occupies time")
        print("PASS: occupied slots, stable previews, overflow, fixed conflicts, boundary times, exclusions, completed tasks, and reminder lead-time fallbacks")
    }
}
