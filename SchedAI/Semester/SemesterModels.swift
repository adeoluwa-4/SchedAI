import Foundation
import SwiftUI

/// What kind of graded thing a syllabus line describes. Drives how much study
/// time SchedAI plans and how far ahead it starts.
enum DeadlineKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case final
    case exam
    case quiz
    case paper
    case project
    case assignment
    case lab
    case reading
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .final: return "Final"
        case .exam: return "Exam"
        case .quiz: return "Quiz"
        case .paper: return "Paper"
        case .project: return "Project"
        case .assignment: return "Assignment"
        case .lab: return "Lab"
        case .reading: return "Reading"
        case .other: return "Deadline"
        }
    }

    var systemImage: String {
        switch self {
        case .final, .exam: return "graduationcap.fill"
        case .quiz: return "questionmark.circle.fill"
        case .paper: return "doc.text.fill"
        case .project: return "hammer.fill"
        case .assignment: return "pencil.and.list.clipboard"
        case .lab: return "flask.fill"
        case .reading: return "book.fill"
        case .other: return "flag.fill"
        }
    }

    /// Study sessions to plan before this deadline: how many, how long, and
    /// how many days ahead to start. Exams get spaced review; homework gets one block.
    var studyPlan: (sessions: Int, minutes: Int, leadDays: Int) {
        switch self {
        case .final: return (5, 60, 12)
        case .exam: return (3, 60, 6)
        case .quiz: return (1, 45, 2)
        case .paper: return (3, 75, 8)
        case .project: return (3, 75, 8)
        case .assignment: return (1, 60, 3)
        case .lab: return (1, 45, 2)
        case .reading: return (1, 45, 2)
        case .other: return (1, 30, 2)
        }
    }

    /// Verb used to name generated study sessions.
    var sessionVerb: String {
        switch self {
        case .final, .exam, .quiz: return "Study for"
        case .paper: return "Write"
        case .project: return "Work on"
        case .assignment, .lab: return "Do"
        case .reading: return "Read"
        case .other: return "Prep"
        }
    }

    var priority: TaskPriority {
        switch self {
        case .final, .exam, .paper, .project: return .high
        case .quiz, .assignment, .lab: return .medium
        case .reading, .other: return .low
        }
    }
}

/// One graded deadline from a syllabus: "CHEM 101 · Midterm 1 · Oct 14".
struct CourseDeadline: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var course: String
    var title: String
    var kind: DeadlineKind
    var due: Date
    /// False when the syllabus gave only a date; the time is then a placeholder.
    var hasTime: Bool = false

    var displayTitle: String { "\(course) \(title)" }
}

/// A recurring class meeting: "CHEM 101 · Mon Wed Fri · 10:00–10:50".
struct ClassMeeting: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var course: String
    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int

    func interval(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        let start = calendar.startOfDay(for: day)
        guard weekdays.contains(calendar.component(.weekday, from: start)),
              endMinutes > startMinutes,
              let s = calendar.date(byAdding: .minute, value: startMinutes, to: start),
              let e = calendar.date(byAdding: .minute, value: endMinutes, to: start)
        else { return nil }
        return DateInterval(start: s, end: e)
    }

    var weekdaySummary: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }  // Monday first
            .map { symbols[$0 - 1] }
            .joined(separator: " ")
    }

    var timeSummary: String {
        func fmt(_ m: Int) -> String {
            let d = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            return d.formatted(date: .omitted, time: .shortened)
        }
        return "\(fmt(startMinutes)) – \(fmt(endMinutes))"
    }
}

/// A stable color per course so CHEM 101 always looks the same everywhere.
enum CourseColor {
    private static let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo, .green, .red]

    static func color(for course: String?) -> Color {
        guard let course, !course.isEmpty else { return .gray }
        let sum = course.uppercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}
