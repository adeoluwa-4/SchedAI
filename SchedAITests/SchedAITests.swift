//
//  SchedAITests.swift
//  SchedAITests
//
//  Created by Adeoluwa Adekoya on 12/18/25.
//

import Testing
import Foundation
@testable import SchedAI

@Suite(.serialized)
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
        #expect(tasks[4].title == "Homework")
        #expect(tasks[5].title == "Bedtime")
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

    @Test func offlineNlpSplitListEntriesSupportsCommasAndNewlines() async throws {
        let parts = OfflineNLP.splitListEntries("study, gym\ncall mom")
        #expect(parts == ["study", "gym", "call mom"])
    }

    @Test func offlineNlpParsesVoicePlanWithAmPmCarry() async throws {
        let input = "I will wake up at 12 PM and do laundry at one for two hours play FIFA three till six then eat dinner at 7:30 and after that go to bed at midnight"
        let tasks = OfflineNLP.parseSafely(input)
        #expect(tasks.count == 5)
        #expect(tasks[0].title == "Wake Up")
        #expect(tasks[1].title == "Do laundry")
        #expect(tasks[2].title == "Play fifa")
        #expect(tasks[3].title == "Eat dinner")
        #expect(tasks[4].title == "Bedtime")

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

    @Test func offlineNlpSplitsUntilPhraseBeforeNextSpokenTime() async throws {
        let now = fixedDate(2026, 5, 1, 6, 0)
        let input = "Get donuts at 7:15 AM had to work at 10 AM do homework do homework for two hours till 12 I have been Bible reading at three be back home by 4:30"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 5)
        guard tasks.count == 5 else { return }

        #expect(tasks.map(\.title) == [
            "Get donuts",
            "Head to work",
            "Homework",
            "Bible reading",
            "Return Home"
        ])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 7)
        #expect(tasks[0].scheduledStart.map { cal.component(.minute, from: $0) } == 15)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 10)
        #expect(tasks[2].scheduledStart.map { cal.component(.hour, from: $0) } == 10)
        #expect(tasks[2].scheduledEnd.map { cal.component(.hour, from: $0) } == 12)
        #expect(tasks[2].estimatedMinutes == 120)
        #expect(tasks[3].scheduledStart.map { cal.component(.hour, from: $0) } == 15)
        #expect(tasks[4].scheduledStart.map { cal.component(.hour, from: $0) } == 16)
        #expect(tasks[4].scheduledStart.map { cal.component(.minute, from: $0) } == 30)
    }

    @Test func offlineNlpStructuresCasualSpeechForCalendar() async throws {
        let now = fixedDate(2026, 5, 2, 23, 54)
        let input = "Tomorrow I'm gonna wake up at 6 AM then I'm gonna go grocery shopping at 7:30 then I'm gonna do homework from 8:15 till about 9:40 then head out the house by 10:15 to go to church be back home around one then I'm doing homework until four then meal prep until 8:30 then be in bed at nine"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 7)
        guard tasks.count == 7 else { return }

        #expect(tasks.map(\.title) == [
            "Wake Up",
            "Grocery Shopping",
            "Homework",
            "Church",
            "Homework",
            "Meal Prep",
            "Bedtime"
        ])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 6)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 7)
        #expect(tasks[1].scheduledStart.map { cal.component(.minute, from: $0) } == 30)
        #expect(tasks[2].scheduledStart.map { cal.component(.hour, from: $0) } == 8)
        #expect(tasks[2].scheduledStart.map { cal.component(.minute, from: $0) } == 15)
        #expect(tasks[2].scheduledEnd.map { cal.component(.hour, from: $0) } == 9)
        #expect(tasks[2].scheduledEnd.map { cal.component(.minute, from: $0) } == 40)
        #expect(tasks[3].scheduledStart.map { cal.component(.hour, from: $0) } == 10)
        #expect(tasks[3].scheduledEnd.map { cal.component(.hour, from: $0) } == 13)
        #expect(tasks[4].scheduledStart.map { cal.component(.hour, from: $0) } == 13)
        #expect(tasks[4].scheduledEnd.map { cal.component(.hour, from: $0) } == 16)
        #expect(tasks[5].scheduledEnd.map { cal.component(.hour, from: $0) } == 20)
        #expect(tasks[5].scheduledEnd.map { cal.component(.minute, from: $0) } == 30)
        #expect(tasks[6].scheduledStart.map { cal.component(.hour, from: $0) } == 21)
    }

    @Test func offlineNlpParsesCompactAfternoonTravelTimes() async throws {
        let now = fixedDate(2026, 6, 6, 9, 32)
        let input = "I'll go to Kansas City today I'll leave the house around 10 for that then go get food around 130 then hang out around Kansas City till four and be home by six"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 4)
        guard tasks.count == 4 else { return }

        #expect(tasks.map(\.title) == [
            "Leave house",
            "Go get food",
            "Hang out around kansas city",
            "Be home"
        ])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 10)
        #expect(tasks[0].scheduledStart.map { cal.component(.minute, from: $0) } == 0)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 13)
        #expect(tasks[1].scheduledStart.map { cal.component(.minute, from: $0) } == 30)
        #expect(tasks[2].scheduledStart.map { cal.component(.hour, from: $0) } == 14)
        #expect(tasks[2].scheduledEnd.map { cal.component(.hour, from: $0) } == 16)
        #expect(tasks[3].scheduledStart.map { cal.component(.hour, from: $0) } == 18)
    }

    @Test func offlineNlpUnderstandsTravelCompactClockSequence() async throws {
        let now = fixedDate(2026, 6, 6, 5, 45)
        let input = "I need to be at the airport by 645 then fly out at 830 and land around 1045"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }
        #expect(tasks.map(\.title) == ["Be at the airport", "Fly out", "Land"])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 6)
        #expect(tasks[0].scheduledStart.map { cal.component(.minute, from: $0) } == 45)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 8)
        #expect(tasks[1].scheduledStart.map { cal.component(.minute, from: $0) } == 30)
        #expect(tasks[2].scheduledStart.map { cal.component(.hour, from: $0) } == 10)
        #expect(tasks[2].scheduledStart.map { cal.component(.minute, from: $0) } == 45)
    }

    @Test func offlineNlpUnderstandsBeforeAndAfterWorkWindows() async throws {
        SchedulingPreferenceStore.resetForTesting()
        defer { SchedulingPreferenceStore.resetForTesting() }

        let now = fixedDate(2026, 6, 6, 6, 0)
        let input = "drop off package before work then pick up prescription after work"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Drop off package", "Pick up prescription"])
        #expect(tasks[0].scheduledStart == nil)
        #expect(tasks[1].scheduledStart == nil)

        let cal = Calendar.current
        #expect(tasks[0].preferredStart.map { cal.component(.hour, from: $0) } == 7)
        #expect(tasks[0].preferredEnd.map { cal.component(.hour, from: $0) } == 9)
        #expect(tasks[1].preferredStart.map { cal.component(.hour, from: $0) } == 17)
        #expect(tasks[1].preferredEnd.map { cal.component(.hour, from: $0) } == 20)
    }

    @Test func offlineNlpUnderstandsSpokenClockAndEndOfDayDeadline() async throws {
        let now = fixedDate(2026, 6, 6, 9, 0)
        let input = "finish lab report by end of day then meet Jordan at one thirty and workout at quarter to seven"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }
        #expect(tasks.map(\.title) == ["Finish lab report", "Meet Jordan", "Workout"])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 17)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 13)
        #expect(tasks[1].scheduledStart.map { cal.component(.minute, from: $0) } == 30)
        #expect(tasks[2].scheduledStart.map { cal.component(.hour, from: $0) } == 18)
        #expect(tasks[2].scheduledStart.map { cal.component(.minute, from: $0) } == 45)
    }

    @Test func offlineNlpCarriesTomorrowAcrossReminderSpeech() async throws {
        let now = fixedDate(2026, 6, 6, 10, 0)
        let input = "can you remind me to turn in my paper tomorrow morning and text Sarah after class"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Turn in my paper", "Text Sarah"])

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        #expect(tasks[0].targetDay.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
        #expect(tasks[1].targetDay.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
        #expect(tasks[0].preferredStart.map { cal.component(.hour, from: $0) } == 9)
        #expect(tasks[1].preferredStart.map { cal.component(.hour, from: $0) } == 15)
    }

    @Test func offlineNlpUnderstandsTodoistStyleAbbreviatedDates() async throws {
        let now = fixedDate(2026, 6, 1, 10, 0) // Monday
        let tasks = OfflineNLP.parseSafely("club meeting Fri @ 7pm", now: now)

        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "Club meeting")

        let start = try #require(task.scheduledStart)
        let cal = Calendar.current
        #expect(cal.component(.weekday, from: start) == 6)
        #expect(cal.component(.hour, from: start) == 19)
    }

    @Test func offlineNlpUnderstandsTomorrowShorthandAndLooseTimes() async throws {
        let now = fixedDate(2026, 6, 6, 10, 0)
        let input = "dentist tom 12:00 then meeting tomorrow 4pm then dinner around like 7ish"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }
        #expect(tasks.map(\.title) == ["Dentist", "Meeting", "Dinner"])

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        #expect(tasks[0].scheduledStart.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 12)
        #expect(tasks[1].scheduledStart.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 16)
        #expect(tasks[2].scheduledStart.map { cal.component(.hour, from: $0) } == 19)
    }

    @Test func offlineNlpUnderstandsMealRelativeWindows() async throws {
        SchedulingPreferenceStore.resetForTesting()
        defer { SchedulingPreferenceStore.resetForTesting() }

        let now = fixedDate(2026, 6, 6, 8, 0)
        let input = "study after lunch and clean room before dinner"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Study", "Clean room"])
        #expect(tasks[0].scheduledStart == nil)
        #expect(tasks[1].scheduledStart == nil)

        let cal = Calendar.current
        #expect(tasks[0].preferredStart.map { cal.component(.hour, from: $0) } == 13)
        #expect(tasks[0].preferredEnd.map { cal.component(.hour, from: $0) } == 15)
        #expect(tasks[1].preferredStart.map { cal.component(.hour, from: $0) } == 16)
        #expect(tasks[1].preferredEnd.map { cal.component(.hour, from: $0) } == 18)
    }

    @Test func offlineNlpUnderstandsWeekendPhrases() async throws {
        let now = fixedDate(2026, 6, 3, 10, 0) // Wednesday
        let tasks = OfflineNLP.parseSafely("wash car this weekend and visit grandma next weekend", now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Wash car", "Visit grandma"])

        let cal = Calendar.current
        #expect(tasks[0].targetDay.map { cal.component(.weekday, from: $0) } == 7)
        #expect(tasks[0].targetDay.map { cal.component(.day, from: $0) } == 6)
        #expect(tasks[1].targetDay.map { cal.component(.weekday, from: $0) } == 7)
        #expect(tasks[1].targetDay.map { cal.component(.day, from: $0) } == 13)
    }

    @Test func offlineNlpUnderstandsNextFridayNightAsPreferredWindow() async throws {
        let now = fixedDate(2026, 6, 1, 10, 0) // Monday
        let tasks = OfflineNLP.parseSafely("movie next Friday night", now: now)

        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "Movie")

        let cal = Calendar.current
        #expect(task.targetDay.map { cal.component(.weekday, from: $0) } == 6)
        #expect(task.preferredStart.map { cal.component(.hour, from: $0) } == 19)
        #expect(task.preferredEnd.map { cal.component(.hour, from: $0) } == 22)
    }

    @Test func offlineNlpUnderstandsBusinessDayAndLaterThisWeek() async throws {
        let now = fixedDate(2026, 6, 3, 10, 0) // Wednesday
        let input = "file expense report next business day and review budget later this week"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["File expense report", "Review budget"])

        let cal = Calendar.current
        #expect(tasks[0].targetDay.map { cal.component(.weekday, from: $0) } == 5)
        #expect(tasks[0].targetDay.map { cal.component(.day, from: $0) } == 4)
        #expect(tasks[1].targetDay.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[1].targetDay.map { cal.component(.day, from: $0) } == 5)
    }

    @Test func offlineNlpExpandsWeekdayRecurringTasks() async throws {
        let now = fixedDate(2026, 6, 1, 8, 0) // Monday
        let tasks = OfflineNLP.parseSafely("weekdays standup at 9a", now: now)

        #expect(tasks.count == 20)
        #expect(tasks.allSatisfy { $0.title == "Standup" })

        let cal = Calendar.current
        let firstWeekdays = Set(tasks.prefix(5).compactMap { task in
            task.scheduledStart.map { cal.component(.weekday, from: $0) }
        })
        #expect(firstWeekdays == Set([2, 3, 4, 5, 6]))
        #expect(tasks.allSatisfy { task in
            task.scheduledStart.map { cal.component(.hour, from: $0) } == 9
        })
    }

    @Test func offlineNlpExpandsMultipleWeekdayRecurringTasks() async throws {
        let now = fixedDate(2026, 6, 1, 8, 0) // Monday
        let tasks = OfflineNLP.parseSafely("every Tuesday and Thursday workout at 7p", now: now)

        #expect(tasks.count == 20)
        #expect(tasks.allSatisfy { $0.title == "Workout" })

        let cal = Calendar.current
        let firstWeekdays = tasks.prefix(2).compactMap { task in
            task.scheduledStart.map { cal.component(.weekday, from: $0) }
        }
        #expect(firstWeekdays == [3, 5])
        #expect(tasks.allSatisfy { task in
            task.scheduledStart.map { cal.component(.hour, from: $0) } == 19
        })
    }

    @Test func offlineNlpUnderstandsEodAndNoonOnWeekday() async throws {
        let now = fixedDate(2026, 6, 1, 9, 0) // Monday
        let input = "send invoice eod Friday and lunch with Maya friday noon"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Send invoice", "Lunch with Maya"])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 17)
        #expect(tasks[1].scheduledStart.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 12)
    }

    @Test func offlineNlpUnderstandsStudentHomeworkAndQuizDeadlines() async throws {
        let now = fixedDate(2026, 6, 1, 10, 0) // Monday
        let input = "math hw due tmr at 11:59 and bio quiz fri noon"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Math homework", "Bio quiz"])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.day, from: $0) } == 2)
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 23)
        #expect(tasks[0].scheduledStart.map { cal.component(.minute, from: $0) } == 59)
        #expect(tasks[1].scheduledStart.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 12)
    }

    @Test func offlineNlpUnderstandsStudentAppointmentsAndLaterTasks() async throws {
        SchedulingPreferenceStore.resetForTesting()
        defer { SchedulingPreferenceStore.resetForTesting() }

        let now = fixedDate(2026, 6, 1, 10, 0)
        let input = "dentist appointmnet after school and do this later"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Dentist appointment", "Do this"])

        let cal = Calendar.current
        #expect(tasks[0].preferredStart.map { cal.component(.hour, from: $0) } == 15)
        #expect(tasks[0].preferredEnd.map { cal.component(.hour, from: $0) } == 18)
        #expect(tasks[1].preferredStart.map { cal.component(.hour, from: $0) } == 15)
        #expect(tasks[1].preferredEnd.map { cal.component(.hour, from: $0) } == 20)
    }

    @Test func offlineNlpUnderstandsStudentSocialAndStudyPlans() async throws {
        SchedulingPreferenceStore.resetForTesting()
        defer { SchedulingPreferenceStore.resetForTesting() }

        let now = fixedDate(2026, 6, 1, 10, 0) // Monday
        let input = "party Friday and study for chem midterm later this week"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Party", "Study for chem midterm"])

        let cal = Calendar.current
        #expect(tasks[0].targetDay.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[0].preferredStart.map { cal.component(.hour, from: $0) } == 20)
        #expect(tasks[0].preferredEnd.map { cal.component(.hour, from: $0) } == 23)
        #expect(tasks[1].targetDay.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[1].preferredStart.map { cal.component(.hour, from: $0) } == 15)
    }

    @Test func offlineNlpUnderstandsCourseCodeFinalPhrasing() async throws {
        let now = fixedDate(2026, 4, 1, 10, 0)
        let tasks = OfflineNLP.parseSafely("add MATH 201 final April 20 9 AM", now: now)

        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "Math 201 final")

        let cal = Calendar.current
        #expect(task.scheduledStart.map { cal.component(.month, from: $0) } == 4)
        #expect(task.scheduledStart.map { cal.component(.day, from: $0) } == 20)
        #expect(task.scheduledStart.map { cal.component(.hour, from: $0) } == 9)
    }

    @Test func offlineNlpUnderstandsExactDatesForErrands() async throws {
        let now = fixedDate(2026, 6, 1, 10, 0)
        let tasks = OfflineNLP.parseSafely("going to the mall on July 14 at 4", now: now)

        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "The mall")

        let cal = Calendar.current
        #expect(task.scheduledStart.map { cal.component(.month, from: $0) } == 7)
        #expect(task.scheduledStart.map { cal.component(.day, from: $0) } == 14)
        #expect(task.scheduledStart.map { cal.component(.hour, from: $0) } == 16)
    }

    @Test func offlineNlpUnderstandsWorkAndOfficeHourRanges() async throws {
        let now = fixedDate(2026, 6, 1, 10, 0) // Monday
        let input = "work shift Friday from 3 to 9 and office hours Wed 1-2"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks.map(\.title) == ["Work shift", "Office hours"])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.weekday, from: $0) } == 6)
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 15)
        #expect(tasks[0].scheduledEnd.map { cal.component(.hour, from: $0) } == 21)
        #expect(tasks[1].scheduledStart.map { cal.component(.weekday, from: $0) } == 4)
        #expect(tasks[1].scheduledStart.map { cal.component(.hour, from: $0) } == 13)
        #expect(tasks[1].scheduledEnd.map { cal.component(.hour, from: $0) } == 14)
    }

    @Test func offlineNlpUnderstandsInterviewsAndRelativeSchoolDates() async throws {
        let now = fixedDate(2026, 6, 1, 10, 0) // Monday
        let input = "interview next Tuesday at 2 then read chapter 8 day after tomorrow and pay rent end of month"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }
        #expect(tasks.map(\.title) == ["Interview", "Read chapter 8", "Pay rent"])

        let cal = Calendar.current
        #expect(tasks[0].scheduledStart.map { cal.component(.weekday, from: $0) } == 3)
        #expect(tasks[0].scheduledStart.map { cal.component(.day, from: $0) } == 9)
        #expect(tasks[0].scheduledStart.map { cal.component(.hour, from: $0) } == 14)
        #expect(tasks[1].targetDay.map { cal.component(.day, from: $0) } == 3)
        #expect(tasks[2].targetDay.map { cal.component(.day, from: $0) } == 30)
    }

    @Test func offlineNlpExpandsWorkdayAndWeekendRepeats() async throws {
        let now = fixedDate(2026, 6, 1, 7, 0) // Monday
        let workdays = OfflineNLP.parseSafely("every workday check canvas at 8am", now: now)
        let weekends = OfflineNLP.parseSafely("every weekend meal prep at 10am", now: now)

        #expect(workdays.count == 20)
        #expect(workdays.allSatisfy { $0.title == "Check canvas" })
        #expect(weekends.count == 12)
        #expect(weekends.allSatisfy { $0.title == "Meal Prep" })

        let cal = Calendar.current
        let firstWorkdaySet = Set(workdays.prefix(5).compactMap { task in
            task.scheduledStart.map { cal.component(.weekday, from: $0) }
        })
        let firstWeekendSet = Set(weekends.prefix(2).compactMap { task in
            task.scheduledStart.map { cal.component(.weekday, from: $0) }
        })
        #expect(firstWorkdaySet == Set([2, 3, 4, 5, 6]))
        #expect(firstWeekendSet == Set([1, 7]))
    }

    @Test func offlineNlpCarriesEnrollmentContextAcrossCourses() async throws {
        let now = fixedDate(2026, 5, 2, 12, 0)
        let input = "Remind me on Monday the fourth to enroll for Jen Ba 205 and for management 596"
        let tasks = OfflineNLP.parseSafely(input, now: now)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        #expect(tasks.map(\.title) == [
            "Enroll for jen ba 205",
            "Enroll for management 596"
        ])

        let cal = Calendar.current
        #expect(tasks[0].targetDay.map { cal.component(.day, from: $0) } == 4)
        #expect(tasks[1].targetDay.map { cal.component(.day, from: $0) } == 4)
        #expect(tasks[0].scheduledStart == nil)
        #expect(tasks[1].scheduledStart == nil)
    }

    @Test func aiServiceMapsStructuredDraftsToTaskItems() async throws {
        let drafts = [
            TaskDraft(
                title: "Enroll for management 596",
                estimatedMinutes: 30,
                priority: "high",
                targetDayISO8601: "2026-05-04",
                scheduledStartISO8601: nil,
                scheduledEndISO8601: nil,
                preferredStartISO8601: nil,
                preferredEndISO8601: nil,
                isPinned: false,
                notes: nil
            ),
            TaskDraft(
                title: "Bible reading",
                estimatedMinutes: 45,
                priority: "medium",
                targetDayISO8601: nil,
                scheduledStartISO8601: "2026-05-04T20:00:00.000Z",
                scheduledEndISO8601: nil,
                preferredStartISO8601: nil,
                preferredEndISO8601: nil,
                isPinned: true,
                notes: nil
            )
        ]

        let tasks = AIService.taskItems(from: drafts)

        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }
        #expect(tasks[0].title == "Enroll for management 596")
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].scheduledStart == nil)
        #expect(tasks[0].targetDay != nil)
        #expect(tasks[1].title == "Bible reading")
        #expect(tasks[1].estimatedMinutes == 45)
        #expect(tasks[1].scheduledStart != nil)
        #expect(tasks[1].scheduledEnd != nil)
        #expect(tasks[1].isPinned)
    }

    @Test func hostedAIImproveDefaultsOnForFirstRun() async throws {
        UserDefaults.standard.removeObject(forKey: "hostedAIConsent")
        let app = await MainActor.run { AppState() }
        let allowed = await MainActor.run { app.hostedAIConsent }
        #expect(allowed)
    }

    @Test func aiServiceCapsStructuredDrafts() async throws {
        let drafts = (1...25).map { index in
            TaskDraft(
                title: "Task \(index)",
                estimatedMinutes: 30,
                priority: "medium",
                targetDayISO8601: nil,
                scheduledStartISO8601: nil,
                scheduledEndISO8601: nil,
                preferredStartISO8601: nil,
                preferredEndISO8601: nil,
                isPinned: false,
                notes: nil
            )
        }

        let tasks = AIService.taskItems(from: drafts)
        #expect(tasks.count == 20)
        #expect(tasks.first?.title == "Task 1")
        #expect(tasks.last?.title == "Task 20")
    }

    @Test func offlineNlpCapsExpandedTaskCount() async throws {
        let now = fixedDate(2026, 6, 5, 10, 0)
        let input = (1...30)
            .map { "task \($0) at \((($0 - 1) % 12) + 1)pm" }
            .joined(separator: " then ")

        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 20)
    }

    @Test func offlineNlpDoesNotNormalizeInvalidNumericDates() async throws {
        let now = fixedDate(2026, 1, 1, 9, 0)
        let tasks = OfflineNLP.parseSafely("Submit form on 2/31 at 9am", now: now)

        guard let target = tasks.first?.targetDay else { return }
        let cal = Calendar.current
        #expect(!(cal.component(.month, from: target) == 3 && cal.component(.day, from: target) == 3))
    }

    @Test func offlineNlpTurnsLaterTodayIntoPreferredWindow() async throws {
        SchedulingPreferenceStore.resetForTesting()
        defer { SchedulingPreferenceStore.resetForTesting() }

        let now = fixedDate(2026, 6, 5, 10, 24)
        let tasks = OfflineNLP.parseSafely("Remind me to add Face ID to scan AI later today", now: now)

        #expect(tasks.count == 1)
        guard let task = tasks.first else { return }

        let cal = Calendar.current
        #expect(task.scheduledStart == nil)
        #expect(task.preferredStart != nil)
        #expect(task.preferredEnd != nil)
        #expect(task.preferredStart.map { cal.component(.hour, from: $0) } == 15)
        #expect(task.targetDay.map { cal.isDate($0, inSameDayAs: now) } == true)
        #expect(!task.isPinned)
    }

    @Test func schedulerRespectsLaterTodayPreferredWindow() async throws {
        let now = fixedDate(2026, 6, 5, 10, 24)
        let preferredStart = fixedDate(2026, 6, 5, 15, 0)
        let preferredEnd = fixedDate(2026, 6, 5, 20, 0)
        var tasks = [
            TaskItem(
                title: "Ask dad about George's number",
                preferredStart: preferredStart,
                preferredEnd: preferredEnd
            )
        ]

        let overflow = Scheduler.planToday(
            tasks: &tasks,
            workStart: fixedDate(2026, 6, 5, 8, 0),
            workEnd: fixedDate(2026, 6, 5, 22, 0),
            day: now,
            now: now
        )

        #expect(overflow == 0)
        #expect(tasks[0].scheduledStart == preferredStart)
    }

    @Test func schedulerKeepsExplicitClockTimesPinned() async throws {
        let now = fixedDate(2026, 6, 5, 10, 24)
        let seven = fixedDate(2026, 6, 5, 19, 0)
        var tasks = [
            TaskItem(
                title: "Fix screenshot timing",
                isPinned: true,
                targetDay: now,
                scheduledStart: seven,
                scheduledEnd: fixedDate(2026, 6, 5, 19, 30)
            )
        ]

        let overflow = Scheduler.planToday(
            tasks: &tasks,
            workStart: fixedDate(2026, 6, 5, 8, 0),
            workEnd: fixedDate(2026, 6, 5, 22, 0),
            day: now,
            now: now
        )

        #expect(overflow == 0)
        #expect(tasks[0].scheduledStart == seven)
        #expect(tasks[0].isPinned)
    }

    @Test func offlineNlpUsesLearnedLaterTodayCorrection() async throws {
        SchedulingPreferenceStore.resetForTesting()
        defer { SchedulingPreferenceStore.resetForTesting() }

        let now = fixedDate(2026, 6, 5, 10, 24)
        SchedulingPreferenceStore.recordCorrection(
            from: "Remind me to ask dad about George's number later today",
            correctedStart: fixedDate(2026, 6, 5, 18, 0),
            durationMinutes: 30
        )

        let tasks = OfflineNLP.parseSafely("Remind me to add Face ID later today", now: now)

        #expect(tasks.count == 1)
        guard let task = tasks.first else { return }

        let cal = Calendar.current
        #expect(task.scheduledStart == nil)
        #expect(task.preferredStart.map { cal.component(.hour, from: $0) } == 18)
        #expect(task.preferredEnd.map { cal.component(.hour, from: $0) } == 20)
    }

    @Test func offlineNlpKeepsClubMeetingTogether() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "Go to club meeting at 4:30 and get a snack at six after that there's a soccer game at nine"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }

        #expect(tasks.map(\.title) == ["Go to club meeting", "Get a snack", "Soccer game"])

        let starts = tasks.compactMap(\.scheduledStart)
        #expect(starts.count == 3)
        guard starts.count == 3 else { return }

        let cal = Calendar.current
        #expect(cal.component(.hour, from: starts[0]) == 16)
        #expect(cal.component(.minute, from: starts[0]) == 30)
        #expect(cal.component(.hour, from: starts[1]) == 18)
        #expect(cal.component(.hour, from: starts[2]) == 21)
    }

    @Test func offlineNlpKeepsDestinationPracticeTogether() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "go to dance practice at five and get dinner at seven"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        #expect(tasks.map(\.title) == ["Go to dance practice", "Get dinner"])

        let starts = tasks.compactMap(\.scheduledStart)
        #expect(starts.count == 2)
        guard starts.count == 2 else { return }

        let cal = Calendar.current
        #expect(cal.component(.hour, from: starts[0]) == 17)
        #expect(cal.component(.hour, from: starts[1]) == 19)
    }

    @Test func offlineNlpCleansThereLeadInsGenerally() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "there is a basketball game at nine and there are some club tryouts at ten"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        #expect(tasks.map(\.title) == ["Basketball game", "Club tryouts"])
    }

    @Test func offlineNlpHandlesSpeechLeadInsAndFuzzyTimes() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "remind me to call mom around five plus schedule dentist appointment about three tomorrow also don't let me forget to pick up groceries near six"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }

        #expect(tasks.map(\.title) == ["Call mom", "Dentist appointment", "Pick up groceries"])

        let starts = tasks.compactMap(\.scheduledStart)
        #expect(starts.count == 3)
        guard starts.count == 3 else { return }

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        #expect(cal.component(.hour, from: starts[0]) == 17)
        #expect(cal.isDate(starts[1], inSameDayAs: tomorrow))
        #expect(cal.component(.hour, from: starts[1]) == 15)
        #expect(cal.component(.hour, from: starts[2]) == 18)
    }

    @Test func offlineNlpSplitsLooseSpeechConnectors() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "email coach at four later meet with Jordan at five also go to club meeting at six"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 3)
        guard tasks.count == 3 else { return }

        #expect(tasks.map(\.title) == ["Email coach", "Meet with Jordan", "Go to club meeting"])

        let starts = tasks.compactMap(\.scheduledStart)
        #expect(starts.count == 3)
        guard starts.count == 3 else { return }

        let cal = Calendar.current
        #expect(cal.component(.hour, from: starts[0]) == 16)
        #expect(cal.component(.hour, from: starts[1]) == 17)
        #expect(cal.component(.hour, from: starts[2]) == 18)
    }

    @Test func offlineNlpCleansPersonalSpeechWrappers() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "I've got a math exam at eight and I should submit essay by 11 pm"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        #expect(tasks.map(\.title) == ["Math exam", "Submit essay"])

        let starts = tasks.compactMap(\.scheduledStart)
        #expect(starts.count == 2)
        guard starts.count == 2 else { return }

        let cal = Calendar.current
        #expect(cal.component(.hour, from: starts[0]) == 20)
        #expect(cal.component(.hour, from: starts[1]) == 23)
    }

    @Test func offlineNlpParsesSpokenDurationsWithoutFor() async throws {
        let now = fixedDate(2026, 4, 22, 12, 0)
        let input = "work on project two hours at four plus review notes takes one hour at seven"
        let tasks = OfflineNLP.parseSafely(input, now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        #expect(tasks.map(\.title) == ["Work on project", "Review notes"])
        #expect(tasks.map(\.estimatedMinutes) == [120, 60])
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

    @Test func offlineNlpAppliesTrailingTonightContextToSiblingTasks() async throws {
        let now = fixedDate(2026, 5, 28, 12, 0)
        let tasks = OfflineNLP.parseSafely("Gym and laundry tonight", now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        #expect(tasks.map(\.title) == ["Gym", "Laundry"])

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        #expect(tasks[0].targetDay.map { cal.startOfDay(for: $0) } == today)
        #expect(tasks[1].targetDay.map { cal.startOfDay(for: $0) } == today)
        #expect(tasks[0].scheduledStart == nil)
        #expect(tasks[1].scheduledStart == nil)
    }

    @Test func offlineNlpDoesNotBleedGlobalDayContextAcrossMixedDayPlan() async throws {
        let now = fixedDate(2026, 5, 28, 12, 0)
        let tasks = OfflineNLP.parseSafely("today gym then tomorrow laundry", now: now)
        #expect(tasks.count == 2)
        guard tasks.count == 2 else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        #expect(tasks[0].targetDay.map { cal.startOfDay(for: $0) } == today)
        #expect(tasks[1].targetDay.map { cal.startOfDay(for: $0) } == tomorrow)
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

    @Test func offlineNlpKeepsEmailObjectWithSendAction() async throws {
        let tasks = OfflineNLP.parseSafely("send investor email 20m")
        #expect(tasks.count == 1)
        guard tasks.count == 1 else { return }
        #expect(tasks[0].title == "Send investor email")
        #expect(tasks[0].estimatedMinutes == 20)
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

    @Test func offlineNlpInfersPmForBareColonReminderAndKeepsToday() async throws {
        let now = fixedDate(2026, 6, 3, 7, 46) // Wednesday morning
        let tasks = OfflineNLP.parseSafely("Remind me at 2:30 to schedule a talk with Chris back on the east side", now: now)
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)

        #expect(task.title == "Schedule a talk with Chris back on the east side")

        let start = try #require(task.scheduledStart)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 3)
        #expect(comps.hour == 14)
        #expect(comps.minute == 30)
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

    @Test func schedulerDoesNotPlaceTodayTasksBeforeNow() async throws {
        let now = fixedDate(2026, 5, 6, 17, 11)
        var tasks: [TaskItem] = [
            TaskItem(title: "Untimed today", estimatedMinutes: 30, priority: .medium, isPinned: false, targetDay: now)
        ]

        _ = Scheduler.planToday(
            tasks: &tasks,
            workStart: fixedDate(2026, 5, 6, 8, 0),
            workEnd: fixedDate(2026, 5, 6, 22, 0),
            day: now,
            now: now,
            bufferMinutes: 0
        )

        let start = try #require(tasks.first?.scheduledStart)
        #expect(start >= fixedDate(2026, 5, 6, 17, 21))
    }

    @Test func schedulerLeavesBlockedAndSkippedTodayTasksUnscheduled() async throws {
        let day = fixedDate(2026, 5, 6, 0, 0)
        var tasks: [TaskItem] = [
            TaskItem(title: "Ready", estimatedMinutes: 30, priority: .medium, targetDay: day),
            TaskItem(title: "Blocked", estimatedMinutes: 30, priority: .medium, planState: .blocked, planStateUpdatedAt: day, targetDay: day),
            TaskItem(title: "Skipped", estimatedMinutes: 30, priority: .medium, planState: .skippedToday, planStateUpdatedAt: day, targetDay: day)
        ]

        _ = Scheduler.planToday(
            tasks: &tasks,
            workStart: fixedDate(2026, 5, 6, 9, 0),
            workEnd: fixedDate(2026, 5, 6, 17, 0),
            day: day,
            bufferMinutes: 0
        )

        #expect(tasks.first(where: { $0.title == "Ready" })?.scheduledStart != nil)
        #expect(tasks.first(where: { $0.title == "Blocked" })?.scheduledStart == nil)
        #expect(tasks.first(where: { $0.title == "Skipped" })?.scheduledStart == nil)
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
