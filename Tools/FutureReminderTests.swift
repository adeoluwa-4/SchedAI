import Foundation

@main
struct FutureReminderTests {
    static func main() throws {
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-09-06T18:00:00Z")!
        let cases: [(String, Date, Int, Int, Int, Int)] = [
            ("a year from now remind me to cancel my Gemini plan", now, 2027, 9, 6, 9),
            ("remind me in two years to cancel my Gemini plan", now, 2028, 9, 6, 9),
            ("six months from now remind me to cancel my Gemini plan", now, 2027, 3, 6, 9),
            ("remind me in 2 years at 3pm to cancel my Gemini plan", now, 2028, 9, 6, 15),
            ("remind me in one year to cancel my Gemini plan", formatter.date(from: "2028-02-29T18:00:00Z")!, 2029, 2, 28, 9),
            ("remind me in one month to cancel my Gemini plan", formatter.date(from: "2027-01-31T18:00:00Z")!, 2027, 2, 28, 9),
        ]
        for (input, reference, year, month, day, hour) in cases {
            for parse in [OfflineNLP.parse, OfflineNLP.parseSafely] {
                let tasks = parse(input, reference)
                guard tasks.count == 1, let start = tasks[0].scheduledStart else {
                    fatalError("Unscheduled or split: \(input): \(tasks)")
                }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: start)
                precondition(components.year == year && components.month == month && components.day == day && components.hour == hour,
                             "Wrong date: \(input): \(components)")
                precondition(tasks[0].title.lowercased() == "cancel my gemini plan", "Wrong title: \(tasks[0].title)")
                precondition(tasks[0].isPinned, "Reminder must retain its proposed time")
                var replanned = tasks
                let calendar = Calendar.current
                _ = Scheduler.planToday(tasks: &replanned,
                                        workStart: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: start)!,
                                        workEnd: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start)!,
                                        day: start, now: reference,
                                        externalBusyIntervals: [DateInterval(start: start, duration: 3600)])
                precondition(replanned[0].scheduledStart == start, "Replanning moved a fixed reminder")
                let restored = try JSONDecoder().decode([TaskItem].self, from: JSONEncoder().encode(tasks))
                precondition(restored[0].scheduledStart == start && restored[0].targetDay == tasks[0].targetDay)
                print("PASS: \(input) → \(start)")
            }
        }
        let dateOnly = OfflineNLP.parseSafely("cancel my Gemini plan in two years", now: now)
        precondition(dateOnly.first?.scheduledStart == nil && dateOnly.first?.targetDay != nil)
        let steps = OfflineNLP.parseSafely("in two years remind me to cancel my Gemini plan and remind me to call Sam in three years", now: now)
        precondition(steps.count == 2 && steps.allSatisfy { $0.scheduledStart != nil })
        print("PASS: date-only task and multi-reminder parsing")
    }
}
