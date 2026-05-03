import Foundation

// Small, deterministic test harness for OfflineNLP without needing Xcode.
// Run:
//   swiftc SchedAI/TaskItem.swift SchedAI/OfflineNLP.swift Tools/NLPTestRunner.swift -o /tmp/nlp && /tmp/nlp

@main
struct NLPTestRunner {
    struct ExpectedTask {
        let title: String
        let minutes: Int?
        let hasTime: Bool?
    }

    struct Case {
        let name: String
        let input: String
        let expectedCount: Int
        let expected: [ExpectedTask]
    }

    static func main() {
        // Fixed reference time so "in 30 mins" and AM/PM inference are stable.
        let now = fixedNow()

        let cases: [Case] = [
            Case(
                name: "Dense day plan",
                input: "eat breakfast at 9 study for 3 hours at 10 play fifa at 2 go for a 15 min walk at 5 do homework at 7 for 2 hrs bed by midnight",
                expectedCount: 6,
                expected: [
                    .init(title: "Eat breakfast", minutes: nil, hasTime: true),
                    .init(title: "Study", minutes: 180, hasTime: true),
                    .init(title: "Play fifa", minutes: nil, hasTime: true),
                    .init(title: "Go for a walk", minutes: 15, hasTime: true),
                    .init(title: "Homework", minutes: 120, hasTime: true),
                    .init(title: "Bedtime", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Dangling preposition cleanup",
                input: "study for 2 hours",
                expectedCount: 1,
                expected: [
                    .init(title: "Study", minutes: 120, hasTime: nil),
                ]
            ),
            Case(
                name: "Multiple time markers (prefix)",
                input: "at 9 breakfast at 10 study at 1 gym",
                expectedCount: 3,
                expected: [
                    .init(title: "Breakfast", minutes: nil, hasTime: true),
                    .init(title: "Study", minutes: nil, hasTime: true),
                    .init(title: "Gym", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Screenshot voice plan with until then next task",
                input: "Get donuts at 7:15 AM had to work at 10 AM do homework do homework for two hours till 12 I have been Bible reading at three be back home by 4:30",
                expectedCount: 5,
                expected: [
                    .init(title: "Get donuts", minutes: nil, hasTime: true),
                    .init(title: "Head to work", minutes: nil, hasTime: true),
                    .init(title: "Homework", minutes: 120, hasTime: true),
                    .init(title: "Bible reading", minutes: nil, hasTime: true),
                    .init(title: "Return Home", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Casual speech becomes calendar titles",
                input: "Tomorrow I'm gonna wake up at 6 AM then I'm gonna go grocery shopping at 7:30 then I'm gonna do homework from 8:15 till about 9:40 then head out the house by 10:15 to go to church be back home around one then I'm doing homework until four then meal prep until 8:30 then be in bed at nine",
                expectedCount: 7,
                expected: [
                    .init(title: "Wake Up", minutes: nil, hasTime: true),
                    .init(title: "Grocery Shopping", minutes: nil, hasTime: true),
                    .init(title: "Homework", minutes: 85, hasTime: true),
                    .init(title: "Church", minutes: 165, hasTime: true),
                    .init(title: "Homework", minutes: nil, hasTime: true),
                    .init(title: "Meal Prep", minutes: nil, hasTime: true),
                    .init(title: "Bedtime", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Enrollment reminder shares date and action",
                input: "Remind me on Monday the fourth to enroll for Jen Ba 205 and for management 596",
                expectedCount: 2,
                expected: [
                    .init(title: "Enroll for jen ba 205", minutes: nil, hasTime: false),
                    .init(title: "Enroll for management 596", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Relative time window",
                input: "in the next 30 minutes do dishes",
                expectedCount: 1,
                expected: [
                    .init(title: "Do dishes", minutes: 30, hasTime: true),
                ]
            ),
            Case(
                name: "Until time implies duration",
                input: "study until 6pm",
                expectedCount: 1,
                expected: [
                    .init(title: "Study", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Time range implies duration",
                input: "from 3 to 4pm homework",
                expectedCount: 1,
                expected: [
                    .init(title: "Homework", minutes: 60, hasTime: true),
                ]
            ),
            Case(
                name: "Quiz review then sleep",
                input: "quiz review at 7 for 45m then sleep by midnight",
                expectedCount: 2,
                expected: [
                    .init(title: "Quiz review", minutes: 45, hasTime: true),
                    .init(title: "Bedtime", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Lab report and lunch",
                input: "tomorrow morning lab report for 2 hours, lunch at noon",
                expectedCount: 1,
                expected: [
                    .init(title: "Lab report, lunch", minutes: 120, hasTime: nil),
                ]
            ),
            Case(
                name: "Between range",
                input: "between 3 and 5 finish essay",
                expectedCount: 1,
                expected: [
                    .init(title: "Finish essay", minutes: 120, hasTime: true),
                ]
            ),
            Case(
                name: "After class call",
                input: "after class call mom",
                expectedCount: 1,
                expected: [
                    .init(title: "Call mom", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "In 20 mins break",
                input: "in 20 mins take a break",
                expectedCount: 1,
                expected: [
                    .init(title: "Take a break", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Gym then dinner",
                input: "gym at 6 dinner at 8",
                expectedCount: 2,
                expected: [
                    .init(title: "Gym", minutes: nil, hasTime: true),
                    .init(title: "Dinner", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Weekly workout",
                input: "every monday workout at 7",
                expectedCount: 12,
                expected: [
                    .init(title: "Workout", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Daily meditate",
                input: "every day meditate 10m",
                expectedCount: 30,
                expected: [
                    .init(title: "Meditate", minutes: 10, hasTime: true),
                ]
            ),
            Case(
                name: "Next Friday meeting",
                input: "next friday project meeting at 2",
                expectedCount: 1,
                expected: [
                    .init(title: "Project meeting", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Around time",
                input: "call advisor around 3",
                expectedCount: 1,
                expected: [
                    .init(title: "Call advisor", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Submit by time",
                input: "submit assignment by 5pm",
                expectedCount: 1,
                expected: [
                    .init(title: "Submit assignment", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Study for 1.5 hours",
                input: "study for 1.5 hours at 7pm",
                expectedCount: 1,
                expected: [
                    .init(title: "Study", minutes: 90, hasTime: true),
                ]
            ),
            Case(
                name: "Group study range",
                input: "from 10 to 11am group study",
                expectedCount: 1,
                expected: [
                    .init(title: "Group study", minutes: 60, hasTime: true),
                ]
            ),
            Case(
                name: "Meeting next Monday",
                input: "meeting next monday at 10am",
                expectedCount: 1,
                expected: [
                    .init(title: "Meeting", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Groceries tomorrow",
                input: "buy groceries tomorrow at 5 pm",
                expectedCount: 1,
                expected: [
                    .init(title: "Buy groceries", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Aug 17 meeting",
                input: "sync meeting on Aug 17 at 4pm for 2 hours",
                expectedCount: 1,
                expected: [
                    .init(title: "Sync meeting", minutes: 120, hasTime: true),
                ]
            ),
            Case(
                name: "Run 2 hours",
                input: "run for 2 hours next wednesday at 5pm",
                expectedCount: 1,
                expected: [
                    .init(title: "Run", minutes: 120, hasTime: true),
                ]
            ),
            Case(
                name: "Lunch for 30",
                input: "lunch at noon for 30 minutes",
                expectedCount: 1,
                expected: [
                    .init(title: "Lunch", minutes: 30, hasTime: true),
                ]
            ),
            Case(
                name: "No time",
                input: "meeting with Tom",
                expectedCount: 1,
                expected: [
                    .init(title: "Meeting with Tom", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Colon time no meridiem",
                input: "class 12:30",
                expectedCount: 1,
                expected: [
                    .init(title: "Class", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Exam then review",
                input: "exam at 7am then review at 9am",
                expectedCount: 2,
                expected: [
                    .init(title: "Exam", minutes: nil, hasTime: true),
                    .init(title: "Review", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Fused actions",
                input: "study eat shower",
                expectedCount: 3,
                expected: [
                    .init(title: "Study", minutes: nil, hasTime: false),
                    .init(title: "Eat", minutes: nil, hasTime: false),
                    .init(title: "Shower", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "And connector",
                input: "do laundry and clean room",
                expectedCount: 2,
                expected: [
                    .init(title: "Do laundry", minutes: nil, hasTime: false),
                    .init(title: "Clean room", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "By midnight bed",
                input: "bed by midnight",
                expectedCount: 1,
                expected: [
                    .init(title: "Bedtime", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Tonight movie",
                input: "tonight movie",
                expectedCount: 1,
                expected: [
                    .init(title: "Movie", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "This afternoon library",
                input: "this afternoon library",
                expectedCount: 1,
                expected: [
                    .init(title: "Library", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Tomorrow evening dinner",
                input: "tomorrow evening dinner with roommates",
                expectedCount: 1,
                expected: [
                    .init(title: "Dinner with roommates", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Prep 2h",
                input: "prep for test 2h",
                expectedCount: 1,
                expected: [
                    .init(title: "Prep for test", minutes: 120, hasTime: false),
                ]
            ),
            Case(
                name: "Read 30m at 8",
                input: "read for 30m at 8",
                expectedCount: 1,
                expected: [
                    .init(title: "Read", minutes: 30, hasTime: true),
                ]
            ),
            Case(
                name: "Before bed",
                input: "before bed journal",
                expectedCount: 1,
                expected: [
                    .init(title: "Journal", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "24h time",
                input: "meeting at 23:45",
                expectedCount: 1,
                expected: [
                    .init(title: "Meeting", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "End of day submit",
                input: "submit essay by end of day",
                expectedCount: 1,
                expected: [
                    .init(title: "Submit essay", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "EOD abbreviation",
                input: "finish notes by eod",
                expectedCount: 1,
                expected: [
                    .init(title: "Finish notes", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Study at 3, gym at 5, dinner at 7",
                input: "study at 3, gym at 5, dinner at 7",
                expectedCount: 3,
                expected: [
                    .init(title: "Study", minutes: nil, hasTime: true),
                    .init(title: "Gym", minutes: nil, hasTime: true),
                    .init(title: "Dinner", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "After lecture email",
                input: "after lecture email professor",
                expectedCount: 1,
                expected: [
                    .init(title: "Email professor", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Text at 730",
                input: "text group at 730",
                expectedCount: 1,
                expected: [
                    .init(title: "Text group", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Shower eat snack study",
                input: "shower eat snack study",
                expectedCount: 4,
                expected: [
                    .init(title: "Shower", minutes: nil, hasTime: false),
                    .init(title: "Eat", minutes: nil, hasTime: false),
                    .init(title: "Snack", minutes: nil, hasTime: false),
                    .init(title: "Study", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Half hour",
                input: "read for half an hour at 9pm",
                expectedCount: 1,
                expected: [
                    .init(title: "Read", minutes: 30, hasTime: true),
                ]
            ),
            Case(
                name: "Quarter past",
                input: "meeting at quarter past six",
                expectedCount: 1,
                expected: [
                    .init(title: "Meeting", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Quarter to",
                input: "call dad at quarter to eight",
                expectedCount: 1,
                expected: [
                    .init(title: "Call dad", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Half past",
                input: "lunch at half past twelve",
                expectedCount: 1,
                expected: [
                    .init(title: "Lunch", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Bedtime routine",
                input: "before bed brush teeth then sleep",
                expectedCount: 2,
                expected: [
                    .init(title: "Brush teeth", minutes: nil, hasTime: false),
                    .init(title: "Bedtime", minutes: nil, hasTime: false),
                ]
            ),
            Case(
                name: "Monthly bill",
                input: "monthly on the 25th pay rent",
                expectedCount: 12,
                expected: [
                    .init(title: "Pay rent", minutes: nil, hasTime: true),
                ]
            ),
            Case(
                name: "Every week on Friday",
                input: "every friday submit reflection at 6pm",
                expectedCount: 12,
                expected: [
                    .init(title: "Submit reflection", minutes: nil, hasTime: true),
                ]
            ),
        ]

        var failures: [String] = []
        for c in cases {
            let tasks = OfflineNLP.parse(c.input, now: now)

            if tasks.count != c.expectedCount {
                failures.append("[\(c.name)] expected count \(c.expectedCount), got \(tasks.count). Parsed: \(tasks.map { $0.title })")
                continue
            }

            for (i, exp) in c.expected.enumerated() {
                if i >= tasks.count { break }
                let t = tasks[i]

                if normalizeTitle(t.title) != normalizeTitle(exp.title) {
                    failures.append("[\(c.name)] task \(i) title expected '\(exp.title)', got '\(t.title)'")
                }
                if let minutes = exp.minutes, t.estimatedMinutes != minutes {
                    failures.append("[\(c.name)] task \(i) minutes expected \(minutes), got \(t.estimatedMinutes)")
                }
                if let hasTime = exp.hasTime {
                    let actual = (t.scheduledStart != nil)
                    if actual != hasTime {
                        failures.append("[\(c.name)] task \(i) hasTime expected \(hasTime), got \(actual)")
                    }
                }
            }
        }

        if failures.isEmpty {
            print("✅ OfflineNLP smoke tests passed (\(cases.count) cases).")
            if !safeModeCheck(now: now) {
                exit(1)
            }
            runBenchmarkIfRequested(now: now)
            exit(0)
        } else {
            print("❌ OfflineNLP smoke tests failed (\(failures.count) issues):")
            for f in failures { print("- \(f)") }
            exit(1)
        }
    }

    private static func runBenchmarkIfRequested(now: Date) {
        guard ProcessInfo.processInfo.environment["NLP_BENCH"] == "1" else { return }

        let inputs = [
            "eat breakfast at 9 study for 3 hours at 10 play fifa at 2 go for a 15 min walk at 5 do homework at 7 for 2 hrs bed by midnight",
            "in the next 30 minutes do dishes then at 7pm dinner",
            "tomorrow morning laundry and clean room then call mom at 4",
            "from 3 to 4pm homework; at 5 workout 45m; by midnight bed",
        ]

        let iterations = 2000
        let start = CFAbsoluteTimeGetCurrent()
        var count = 0
        for _ in 0..<iterations {
            for i in inputs {
                count += OfflineNLP.parse(i, now: now).count
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let perParseMs = (elapsed / Double(iterations * inputs.count)) * 1000.0
        print(String(format: "⏱️  Benchmark: %.3f ms/parse (totalTasks=%d)", perParseMs, count))
    }

    private static func fixedNow() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2026
        comps.month = 2
        comps.day = 22
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return comps.date ?? Date(timeIntervalSince1970: 0)
    }

    private static func normalizeTitle(_ title: String) -> String {
        let lowered = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let stripped = collapsed.replacingOccurrences(of: #"[.,;:!?'\"\(\)\[\]\{\}\-]"#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeModeCheck(now: Date) -> Bool {
        let t = OfflineNLP.parseSafely("study at 3", now: now)
        if let first = t.first, first.scheduledStart != nil {
            print("❌ Safe mode check failed: ambiguous time was scheduled.")
            return false
        }
        print("✅ Safe mode check passed.")
        return true
    }
}
