import Testing
import Foundation
@testable import SchedAI

/// Syllabus reading, study-session spacing, catch-up, and classes blocking time.
struct StudentPlannerTests {
    private let cal = Calendar.current

    /// Monday, Nov 23, 2026, 9:00 AM.
    private var now: Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 23; c.hour = 9
        return cal.date(from: c)!
    }

    private func day(_ offset: Int, _ hour: Int = 0) -> Date {
        let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    private func offset(of date: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day!
    }

    // MARK: Syllabus reading

    private let syllabus = """
    CHEM 101: General Chemistry I — Fall 2026
    Lecture: MWF 10:00-10:50 AM, Hammond Hall 120
    Week 13 (Nov 24): Chapter 9 reading — Thermochemistry
    Problem Set 7 due Nov 25
    Quiz 4 on Friday, Nov 27
    Week 14 (Dec 1): Lab report 5 due Dec 3 at 11:59 PM
    Midterm 2 — December 4
    Dec 8: Review session (optional)
    Sep 4: Intro to atoms
    Final Exam: December 15, 8:00 AM
    """

    @Test func findsCourseName() {
        #expect(SyllabusReader.read(syllabus, now: now).course == "CHEM 101")
    }

    @Test func findsGradedDeadlinesAndSkipsTopics() {
        let result = SyllabusReader.read(syllabus, now: now)
        let kinds = result.deadlines.map(\.kind)
        #expect(kinds == [.reading, .assignment, .quiz, .paper, .exam, .final])
        // "Review session" and "Intro to atoms" are not graded and must be skipped.
        #expect(!result.deadlines.contains { $0.title.localizedCaseInsensitiveContains("review") })
        #expect(!result.deadlines.contains { $0.title.localizedCaseInsensitiveContains("atoms") })
    }

    @Test func readsDatesAndTimes() {
        let result = SyllabusReader.read(syllabus, now: now)
        let midterm = result.deadlines.first { $0.kind == .exam }!
        #expect(cal.component(.month, from: midterm.due) == 12)
        #expect(cal.component(.day, from: midterm.due) == 4)
        #expect(midterm.hasTime == false)

        let final = result.deadlines.first { $0.kind == .final }!
        #expect(final.hasTime)
        #expect(cal.component(.hour, from: final.due) == 8)
    }

    @Test func cleansTitles() {
        let titles = SyllabusReader.read(syllabus, now: now).deadlines.map(\.title)
        #expect(titles.contains("Problem Set 7"))
        #expect(titles.contains("Midterm 2"))
        #expect(titles.contains("Lab report 5"))
    }

    @Test func prefersTheDueDateOverAWeekLabel() {
        let lab = SyllabusReader.read(syllabus, now: now).deadlines.first { $0.title.hasPrefix("Lab report") }!
        #expect(cal.component(.month, from: lab.due) == 12)
        #expect(cal.component(.day, from: lab.due) == 3)
        #expect(lab.hasTime)
    }

    @Test func readsClassTimes() {
        let meeting = SyllabusReader.read(syllabus, now: now).classes.first
        #expect(meeting?.weekdays == [2, 4, 6])
        #expect(meeting?.startMinutes == 10 * 60)
        #expect(meeting?.endMinutes == 10 * 60 + 50)
    }

    @Test func readsTuesdayThursdayAfternoonClass() {
        let m = SyllabusReader.classMeeting(in: "Class meets TTh 2:00–3:15 PM in Room 4", course: "PSYC 210")
        #expect(m?.weekdays == [3, 5])
        #expect(m?.startMinutes == 14 * 60)
        #expect(m?.endMinutes == 15 * 60 + 15)
    }

    @Test func yearlessDateInThePastRollsToNextYear() {
        let result = SyllabusReader.read("ECON 200\nMidterm: Jan 20", now: now)
        #expect(result.deadlines.first.map { cal.component(.year, from: $0.due) } == 2027)
    }

    // MARK: Study sessions

    @Test func examGetsSpacedSessionsBeforeTheDay() {
        let exam = CourseDeadline(course: "CHEM 101", title: "Midterm 2", kind: .exam, due: day(6, 10))
        let sessions = StudyPlanner.sessions(for: exam, now: now)
        #expect(sessions.count == 3)
        let offsets = sessions.compactMap(\.targetDay).map(offset(of:))
        #expect(offsets == [1, 3, 5])           // spaced, last one the day before
        #expect(sessions.allSatisfy { $0.studyForDeadlineID == exam.id && $0.course == "CHEM 101" })
        #expect(sessions.first?.title == "Study for CHEM 101 Midterm 2 (1/3)")
    }

    @Test func closeDeadlineCompressesSessions() {
        let exam = CourseDeadline(course: "CHEM 101", title: "Midterm", kind: .exam, due: day(2, 10))
        let offsets = StudyPlanner.sessions(for: exam, now: now).compactMap(\.targetDay).map(offset(of:))
        #expect(offsets == [0, 1])
    }

    @Test func pastDeadlineGetsNoSessions() {
        let old = CourseDeadline(course: "X", title: "Quiz", kind: .quiz, due: day(-1))
        #expect(StudyPlanner.sessions(for: old, now: now).isEmpty)
    }

    // MARK: Catch-up

    @Test func catchUpMovesMissedSessionsBeforeDeadline() {
        let exam = CourseDeadline(course: "CHEM 101", title: "Midterm", kind: .exam, due: day(4, 10))
        let missed = TaskItem(title: "Study 1", estimatedMinutes: 60, targetDay: day(-2), course: "CHEM 101", studyForDeadlineID: exam.id)
        let alsoMissed = TaskItem(title: "Study 2", estimatedMinutes: 60, targetDay: day(-1), course: "CHEM 101", studyForDeadlineID: exam.id)
        let upcoming = TaskItem(title: "Study 3", estimatedMinutes: 60, targetDay: day(3), course: "CHEM 101", studyForDeadlineID: exam.id)

        let progress = StudyPlanner.progress(for: exam, tasks: [missed, alsoMissed, upcoming], now: now)
        #expect(progress.behind == 2)
        #expect(progress.daysLeft == 4)

        let result = StudyPlanner.catchUp(tasks: [missed, alsoMissed, upcoming], deadlines: [exam], now: now)
        #expect(result.moved == 2)
        let days = result.tasks.compactMap(\.targetDay).map(offset(of:))
        #expect(days.allSatisfy { (0...3).contains($0) })
        // Spread out, not piled on one day, and not onto day 3 which already has a session.
        #expect(Set(days).count == 3)
        #expect(StudyPlanner.progress(for: exam, tasks: result.tasks, now: now).behind == 0)
    }

    @Test func catchUpLeavesSessionsForPassedDeadlines() {
        let quiz = CourseDeadline(course: "X", title: "Quiz", kind: .quiz, due: day(-1))
        let missed = TaskItem(title: "Study", targetDay: day(-2), studyForDeadlineID: quiz.id)
        let result = StudyPlanner.catchUp(tasks: [missed], deadlines: [quiz], now: now)
        #expect(result.moved == 0)
        #expect(result.tooLate == 1)
    }

    // MARK: Classes block time

    @Test func classMeetingOnlyOnItsDays() {
        let chem = ClassMeeting(course: "CHEM 101", weekdays: [2, 4, 6], startMinutes: 600, endMinutes: 650)
        #expect(chem.interval(on: day(0)) != nil)   // Monday
        #expect(chem.interval(on: day(1)) == nil)   // Tuesday
    }

    @Test func schedulerPlansStudyAroundClass() {
        let chem = ClassMeeting(course: "CHEM 101", weekdays: [2], startMinutes: 9 * 60 + 30, endMinutes: 11 * 60)
        var tasks = [TaskItem(title: "Study", estimatedMinutes: 60, targetDay: day(0))]
        _ = Scheduler.planToday(
            tasks: &tasks, workStart: day(0, 9), workEnd: day(0, 17), day: day(0), now: day(0, 7),
            externalBusyIntervals: [chem.interval(on: day(0))!]
        )
        let start = tasks[0].scheduledStart!
        #expect(start >= day(0, 11))  // after class, not during it
    }

    @Test func oldTasksWithoutCourseStillLoad() throws {
        let json = #"{"title":"Legacy","deadline":0}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TaskItem.self, from: json)
        #expect(decoded.course == nil && decoded.studyForDeadlineID == nil)
    }
}
