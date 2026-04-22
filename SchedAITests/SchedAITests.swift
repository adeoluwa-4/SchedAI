//
//  SchedAITests.swift
//  SchedAITests
//
//  Created by Adeoluwa Adekoya on 12/18/25.
//

import Testing
import Foundation
@testable import SchedAI

struct SchedAITests {

    private func fixedDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func offlineNlpSplitsMultipleTimes() async throws {
        let tasks = OfflineNLP.parse("at 9 breakfast at 10 study at 1 gym")
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "Breakfast")
        #expect(tasks[1].title == "Study")
        #expect(tasks[2].title == "Gym")
        #expect(tasks.allSatisfy { $0.scheduledStart != nil })
    }

    @Test func offlineNlpCleansDanglingPrepositions() async throws {
        let tasks = OfflineNLP.parse("study for 2 hours")
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Study")
    }

    @Test func offlineNlpParsesDenseDayPlan() async throws {
        let input = "eat breakfast at 9 study for 3 hours at 10 play fifa at 2 go for a 15 min walk at 5 do homework at 7 for 2 hrs bed by midnight"
        let tasks = OfflineNLP.parse(input)
        #expect(tasks.count == 6)
        #expect(tasks[0].title == "Eat breakfast")
        #expect(tasks[1].title == "Study")
        #expect(tasks[2].title == "Play fifa")
        #expect(tasks[3].title == "Go for a walk")
        #expect(tasks[4].title == "Do homework")
        #expect(tasks[5].title == "Bed")
        #expect(tasks[1].estimatedMinutes == 180)
        #expect(tasks[3].estimatedMinutes == 15)
        #expect(tasks[4].estimatedMinutes == 120)
    }

    @Test func offlineNlpNormalizeInputReplacesWordNumbersAndKeywords() async throws {
        let normalized = OfflineNLP.normalizeInput("One task at Noon, then sleep at midnight and study for two hours")
        #expect(normalized.contains("1 task"))
        #expect(normalized.contains("12 pm"))
        #expect(normalized.contains("12 am"))
        #expect(normalized.contains("2 hours"))
    }

    @Test func offlineNlpSplitTasksByConnectors() async throws {
        let input = "wake up at 12 pm and do laundry at one for two hours then play fifa 3 till 6 after that go to bed at midnight"
        let parts = OfflineNLP.splitTasks(input)
        #expect(parts.count == 4)
        #expect(parts[0].contains("wake up"))
        #expect(parts[1].contains("do laundry"))
        #expect(parts[2].contains("play fifa"))
        #expect(parts[3].contains("go to bed"))
    }

    @Test func offlineNlpParsesVoicePlanWithAmPmCarry() async throws {
        let input = "I will wake up at 12 PM and do laundry at one for two hours play FIFA three till six then eat dinner at 7:30 and after that go to bed at midnight"
        let tasks = OfflineNLP.parseSafely(input)
        #expect(tasks.count == 5)
        #expect(tasks[0].title == "Wake up")
        #expect(tasks[1].title == "Do laundry")
        #expect(tasks[2].title == "Play fifa")
        #expect(tasks[3].title == "Eat dinner")
        #expect(tasks[4].title == "Go to bed")

        let cal = Calendar.current
        let h0 = tasks[0].scheduledStart.map { cal.component(.hour, from: $0) }
        let h1 = tasks[1].scheduledStart.map { cal.component(.hour, from: $0) }
        let h2 = tasks[2].scheduledStart.map { cal.component(.hour, from: $0) }
        let h3 = tasks[3].scheduledStart.map { cal.component(.hour, from: $0) }
        let h4 = tasks[4].scheduledStart.map { cal.component(.hour, from: $0) }

        #expect(h0 == 12)
        #expect(h1 == 13)
        #expect(h2 == 15)
        #expect(h3 == 19)
        #expect(h4 == 0)
        #expect(tasks[1].estimatedMinutes == 120)
        #expect(tasks[2].estimatedMinutes == 180)
    }

    @Test func offlineNlpDefaultsStudyTimeToPmAfterMorningContext() async throws {
        let input = "eat breakfast at 8 and study at 4"
        let tasks = OfflineNLP.parseSafely(input)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        let cal = Calendar.current
        let breakfastHour = tasks[0].scheduledStart.map { cal.component(.hour, from: $0) }
        let studyHour = tasks[1].scheduledStart.map { cal.component(.hour, from: $0) }

        #expect(breakfastHour == 8)
        #expect(studyHour == 16)
    }

    @Test func offlineNlpNormalizesTurnNikeToTonight() async throws {
        let normalized = OfflineNLP.normalizeInput("turn Nike dinner at 7")
        #expect(normalized.contains("tonight"))

        let tasks = OfflineNLP.parseSafely("turn Nike dinner at 7")
        #expect(tasks.count == 1)
        let hour = tasks[0].scheduledStart.map { Calendar.current.component(.hour, from: $0) }
        #expect(hour == 19)
    }

    @Test func offlineNlpParsesTomorrowMisspelling() async throws {
        let now = fixedDate(2026, 3, 21, 10, 0)
        let tasks = OfflineNLP.parseSafely("study tommporw at 4", now: now)
        #expect(tasks.count == 1)
        guard let start = tasks.first?.scheduledStart else {
            #expect(false)
            return
        }

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        #expect(cal.isDate(start, inSameDayAs: tomorrow))
        #expect(cal.component(.hour, from: start) == 16)
    }

    @Test func offlineNlpParsesRelativeDaysFromNow() async throws {
        let now = fixedDate(2026, 3, 21, 10, 0)
        let tasks = OfflineNLP.parseSafely("do laundry 2 days from now at 5", now: now)
        #expect(tasks.count == 1)
        guard let start = tasks.first?.scheduledStart else {
            #expect(false)
            return
        }

        let cal = Calendar.current
        let target = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        #expect(cal.isDate(start, inSameDayAs: target))
        #expect(cal.component(.hour, from: start) == 17)
    }

    @Test func offlineNlpRespectsTodayThenTomorrowSequenceWithoutTimes() async throws {
        let now = fixedDate(2026, 4, 17, 9, 0)
        let tasks = OfflineNLP.parseSafely("today i am doing laundry then tomorrow i am doing study", now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        let firstDay = tasks[0].targetDay.map { cal.startOfDay(for: $0) }
        let secondDay = tasks[1].targetDay.map { cal.startOfDay(for: $0) }

        #expect(firstDay == today)
        #expect(secondDay == tomorrow)
    }

    @Test func offlineNlpCarriesTodayContextAcrossSiblingActionsBeforeTomorrow() async throws {
        let now = fixedDate(2026, 4, 17, 9, 0)
        let tasks = OfflineNLP.parseSafely(
            "today take a headshot and get ai into the app store then tomorrow study",
            now: now
        )
        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        let firstDay = tasks[0].targetDay.map { cal.startOfDay(for: $0) }
        let secondDay = tasks[1].targetDay.map { cal.startOfDay(for: $0) }
        let thirdDay = tasks[2].targetDay.map { cal.startOfDay(for: $0) }

        #expect(firstDay == today)
        #expect(secondDay == today)
        #expect(thirdDay == tomorrow)
    }

    @Test func offlineNlpParsesRelativeWeeksFromNowWithTypo() async throws {
        let now = fixedDate(2026, 3, 21, 10, 0)
        let tasks = OfflineNLP.parseSafely("meeting 2 weeks from noe at 6 pm", now: now)
        #expect(tasks.count == 1)
        guard let start = tasks.first?.scheduledStart else {
            #expect(false)
            return
        }

        let cal = Calendar.current
        let target = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: now))!
        #expect(cal.isDate(start, inSameDayAs: target))
        #expect(cal.component(.hour, from: start) == 18)
    }

    @Test func offlineNlpParsesWeekdayOrdinalDate() async throws {
        let now = fixedDate(2026, 3, 1, 9, 0)
        let tasks = OfflineNLP.parseSafely("call mom wednesday the 4th at 3 pm", now: now)
        #expect(tasks.count == 1)
        guard let start = tasks.first?.scheduledStart else {
            #expect(false)
            return
        }

        let cal = Calendar.current
        #expect(cal.component(.day, from: start) == 4)
        #expect(cal.component(.weekday, from: start) == 4) // Wednesday
    }

    @Test func offlineNlpDefaultsNextMonthToFirstDay() async throws {
        let now = fixedDate(2026, 3, 21, 10, 0)
        let tasks = OfflineNLP.parseSafely("submit report next motnh at 9 am", now: now)
        #expect(tasks.count == 1)
        guard let start = tasks.first?.scheduledStart else {
            #expect(false)
            return
        }

        let cal = Calendar.current
        #expect(cal.component(.year, from: start) == 2026)
        #expect(cal.component(.month, from: start) == 4)
        #expect(cal.component(.day, from: start) == 1)
        #expect(cal.component(.hour, from: start) == 9)
    }

    @Test func offlineNlpParsesRelativeNextWindowWithStepPipeline() async throws {
        let now = fixedDate(2026, 3, 21, 10, 1)
        let tasks = OfflineNLP.parseSafely("in the next 30 minutes do dishes", now: now)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Do dishes")
        #expect(tasks[0].estimatedMinutes == 30)
        #expect(tasks[0].scheduledStart != nil)
    }

    @Test func offlineNlpHandlesDecimalDurationInStepPipeline() async throws {
        let tasks = OfflineNLP.parseSafely("study for 1.5 hours at 7 pm")
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Study")
        #expect(tasks[0].estimatedMinutes == 90)
    }

    @Test func offlineNlpAppliesRecurrenceInStepPipeline() async throws {
        let tasks = OfflineNLP.parseSafely("every monday workout at 7")
        #expect(tasks.count == 12)
        #expect(tasks.allSatisfy { $0.title == "Workout" })
        #expect(tasks.allSatisfy { $0.scheduledStart != nil })
    }

    @Test func offlineNlpCleansDateContextFromTitleInStepPipeline() async throws {
        let now = fixedDate(2026, 3, 21, 10, 0)
        let tasks = OfflineNLP.parseSafely("meeting next monday at 10am", now: now)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Meeting")
    }

    @Test func offlineNlpDoesNotForceClockTimeForBeforeBedContext() async throws {
        let tasks = OfflineNLP.parseSafely("before bed brush teeth")
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Brush teeth")
        #expect(tasks[0].scheduledStart == nil)
    }

    @Test func offlineNlpDoesNotSplitOnCommaByDefault() async throws {
        let tasks = OfflineNLP.parseSafely("tomorrow morning lab report for 2 hours, lunch at noon")
        #expect(tasks.count == 1)
        guard tasks.count == 1 else { return }
        #expect(tasks[0].title.contains("Lab report"))
    }

    @Test func offlineNlpSplitsImperativeActionsIntoThreeTasks() async throws {
        let tasks = OfflineNLP.parseSafely("take a headshot and get ai into the app store and have dinner with friends at eight")
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "Take a headshot")
        #expect(tasks[1].title == "Get ai into the app store")
        #expect(tasks[2].title == "Have dinner with friends")
        let hour = tasks[2].scheduledStart.map { Calendar.current.component(.hour, from: $0) }
        #expect(hour == 20)
    }

    @Test func offlineNlpSplitsSpeechNoiseVariant() async throws {
        let tasks = OfflineNLP.parseSafely("take text from headshot get get ai to the app store and have dinner at eight")
        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }
        #expect(tasks[0].title.contains("Take"))
        #expect(tasks[1].title.lowercased().contains("app store"))
        #expect(tasks[2].title == "Have dinner")
    }

    @Test func offlineNlpCarriesPmAcrossEveningSequence() async throws {
        let now = fixedDate(2026, 4, 10, 16, 11)
        let input = "i'll be back in my hotel at 4:45 then i'll be ready at 5:30 for dinner and i have my met gala at 6 pm play fifa and go to bed at midnight"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count >= 4)
        guard tasks.count >= 2 else { return }

        let cal = Calendar.current
        let backHour = tasks[0].scheduledStart.map { cal.component(.hour, from: $0) }
        let readyHour = tasks[1].scheduledStart.map { cal.component(.hour, from: $0) }
        #expect(backHour == 16)
        #expect(readyHour == 17)
    }

    @Test func offlineNlpWeeklyRecurrenceSkipsPastTimeToday() async throws {
        let now = fixedDate(2026, 4, 23, 22, 0) // Thursday 10 PM
        let tasks = OfflineNLP.parseSafely("every thursday workout at 7", now: now)
        #expect(tasks.count == 12)
        guard let first = tasks.first?.scheduledStart else {
            #expect(false)
            return
        }

        let cal = Calendar.current
        let dayDelta = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: first)).day
        #expect(dayDelta == 7)
        #expect(cal.component(.hour, from: first) == 19)
    }

    @Test func schedulerPlacesUntimedTasksAroundExternalBusyIntervals() async throws {
        var tasks: [TaskItem] = [
            TaskItem(title: "Untimed A", estimatedMinutes: 30, priority: .medium, isPinned: false),
            TaskItem(title: "Fixed", estimatedMinutes: 30, priority: .medium, isPinned: true, scheduledStart: fixedDate(2026, 4, 10, 13, 0), scheduledEnd: fixedDate(2026, 4, 10, 13, 30)),
            TaskItem(title: "Untimed B", estimatedMinutes: 30, priority: .medium, isPinned: false)
        ]

        let workStart = fixedDate(2026, 4, 10, 9, 0)
        let workEnd = fixedDate(2026, 4, 10, 17, 0)
        let busy = [DateInterval(start: fixedDate(2026, 4, 10, 9, 0), end: fixedDate(2026, 4, 10, 10, 0))]

        _ = Scheduler.planToday(
            tasks: &tasks,
            workStart: workStart,
            workEnd: workEnd,
            day: fixedDate(2026, 4, 10, 0, 0),
            bufferMinutes: 0,
            externalBusyIntervals: busy
        )

        let fixed = tasks.first(where: { $0.title == "Fixed" })
        let fixedHour = fixed?.scheduledStart.map { Calendar.current.component(.hour, from: $0) }
        let fixedMinute = fixed?.scheduledStart.map { Calendar.current.component(.minute, from: $0) }
        #expect(fixedHour == 13)
        #expect(fixedMinute == 0)

        let untimedStarts = tasks
            .filter { $0.title.hasPrefix("Untimed") }
            .compactMap(\.scheduledStart)
            .sorted()

        #expect(untimedStarts.count == 2)
        guard untimedStarts.count == 2 else { return }
        #expect(untimedStarts[0] >= fixedDate(2026, 4, 10, 10, 0))
    }

    @Test func schedulerRespectsTargetDayAssignments() async throws {
        let cal = Calendar.current
        let today = fixedDate(2026, 4, 17, 0, 0)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        var tasks: [TaskItem] = [
            TaskItem(title: "Today task", estimatedMinutes: 30, priority: .medium, targetDay: today),
            TaskItem(title: "Tomorrow task", estimatedMinutes: 30, priority: .medium, targetDay: tomorrow)
        ]

        _ = Scheduler.planToday(
            tasks: &tasks,
            workStart: fixedDate(2026, 4, 17, 9, 0),
            workEnd: fixedDate(2026, 4, 17, 17, 0),
            day: today,
            bufferMinutes: 0
        )

        let scheduledToday = tasks.first(where: { $0.title == "Today task" })?.scheduledStart
        let scheduledTomorrow = tasks.first(where: { $0.title == "Tomorrow task" })?.scheduledStart

        #expect(scheduledToday != nil)
        #expect(scheduledTomorrow == nil)
    }

}
