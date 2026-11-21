import Testing
import Foundation
@testable import SchedAI

/// Covers the redesign's scheduling rules: deadlines first, deadline caps,
/// and filling gaps without moving already-placed tasks.
struct SchedulerV2Tests {
    private let cal = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2030; c.month = 3; c.day = 4 + dayOffset
        c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    private var day: Date { cal.startOfDay(for: at(9)) }

    @Test func dueSoonTaskBeatsHigherPriority() {
        var tasks = [
            TaskItem(title: "High priority essay", estimatedMinutes: 60, priority: .high, targetDay: day),
            TaskItem(title: "Low priority form", estimatedMinutes: 30, priority: .low, targetDay: day, deadline: at(12))
        ]
        _ = Scheduler.planToday(tasks: &tasks, workStart: at(9), workEnd: at(17), day: day, now: at(7))
        let form = tasks.first { $0.title.hasPrefix("Low") }!
        let essay = tasks.first { $0.title.hasPrefix("High") }!
        #expect(form.scheduledStart! < essay.scheduledStart!)
    }

    @Test func farDeadlineDoesNotJumpTheQueue() {
        var tasks = [
            TaskItem(title: "High", estimatedMinutes: 60, priority: .high, targetDay: day),
            TaskItem(title: "Low", estimatedMinutes: 30, priority: .low, targetDay: day, deadline: at(9, dayOffset: 20))
        ]
        _ = Scheduler.planToday(tasks: &tasks, workStart: at(9), workEnd: at(17), day: day, now: at(7))
        let high = tasks.first { $0.title == "High" }!
        let low = tasks.first { $0.title == "Low" }!
        #expect(high.scheduledStart! < low.scheduledStart!)
    }

    @Test func taskFinishesBeforeItsDeadline() {
        var tasks = [
            TaskItem(title: "Meeting", estimatedMinutes: 60, isPinned: true, targetDay: day, scheduledStart: at(9), scheduledEnd: at(10)),
            TaskItem(title: "Report", estimatedMinutes: 45, targetDay: day, deadline: at(11))
        ]
        let overflow = Scheduler.planToday(tasks: &tasks, workStart: at(9), workEnd: at(17), day: day, now: at(7))
        let report = tasks.first { $0.title == "Report" }!
        #expect(overflow == 0)
        #expect(report.scheduledEnd! <= at(11))
    }

    @Test func fillingGapsKeepsExistingPlacements() {
        var tasks = [
            TaskItem(title: "Already placed", estimatedMinutes: 60, targetDay: day, scheduledStart: at(13), scheduledEnd: at(14)),
            TaskItem(title: "New", estimatedMinutes: 30, priority: .high, targetDay: day)
        ]
        _ = Scheduler.planToday(tasks: &tasks, workStart: at(9), workEnd: at(17), day: day, now: at(7), keepExistingSchedules: true)
        let placed = tasks.first { $0.title == "Already placed" }!
        let new = tasks.first { $0.title == "New" }!
        #expect(placed.scheduledStart == at(13))
        #expect(placed.isPinned == false)
        #expect(new.scheduledStart != nil)
    }

    @Test func deadlineSurvivesSaveAndLoad() throws {
        let task = TaskItem(title: "Due", deadline: at(15))
        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        #expect(decoded.deadline == at(15))
    }

    @Test func oldSavedTasksWithoutDeadlineStillLoad() throws {
        let json = #"{"title":"Legacy task"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TaskItem.self, from: json)
        #expect(decoded.deadline == nil)
    }
}
