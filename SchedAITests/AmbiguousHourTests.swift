import Testing
import Foundation
@testable import SchedAI

/// A bare hour ("at 9") with no am/pm and no time-of-day words should land on
/// the next sensible occurrence, not one that has already passed today.
struct AmbiguousHourTests {
    private let cal = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2030; c.month = 3; c.day = 4; c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    // A lone ambiguous hour ("workout at 9" by itself) is deliberately left
    // untimed by the parser. The bug showed up when it came with other tasks.
    private let dump = "finish stats homework 45m urgent\ncall dad later today\nworkout at 9 for 45 minutes"

    private func workoutStart(_ text: String, now: Date) -> Date? {
        OfflineNLP.parseSafely(text, now: now).first { $0.title.lowercased().contains("workout") }?.scheduledStart
    }

    @Test func eveningBareHourMeansTonight() {
        // The reported bug: typed at 6:54 PM, "at 9" was placed at 9:00 AM (already past).
        let start = workoutStart(dump, now: at(18, 54))
        #expect(start.map { cal.component(.hour, from: $0) } == 21)
        #expect(start.map { cal.isDate($0, inSameDayAs: at(9)) } == true)
    }

    @Test func morningBareHourStaysMorning() {
        let start = workoutStart("call dad\nworkout at 9 for 45 minutes", now: at(7, 0))
        #expect(start.map { cal.component(.hour, from: $0) } == 9)
    }

    @Test func middayBareHourMovesToEvening() {
        let start = workoutStart("call dad\nworkout at 10", now: at(12, 30))
        #expect(start.map { cal.component(.hour, from: $0) } == 22)
    }

    @Test func explicitMeridiemIsNeverChanged() {
        #expect(workoutStart("call dad\nworkout at 9am", now: at(18, 54)).map { cal.component(.hour, from: $0) } == 9)
        #expect(workoutStart("call dad\nworkout at 9 pm", now: at(7, 0)).map { cal.component(.hour, from: $0) } == 21)
    }

    @Test func morningWordsStillWin() {
        #expect(workoutStart("call dad\nworkout at 8 in the morning", now: at(18, 0)).map { cal.component(.hour, from: $0) } == 8)
    }

    @Test func tomorrowIsNotShifted() {
        let start = workoutStart("call dad\nworkout tomorrow at 9", now: at(18, 54))
        #expect(start.map { cal.component(.hour, from: $0) } == 9)
    }
}
