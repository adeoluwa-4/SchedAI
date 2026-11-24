import Foundation
import Combine

/// Holds the student's semester: class meetings and course deadlines.
/// Study sessions themselves are ordinary tasks in `AppState`, linked back to
/// a deadline by `TaskItem.studyForDeadlineID`.
///
/// Kept separate from `AppState` on purpose: AppState is already too large,
/// and the semester has its own file and lifecycle.
@MainActor
final class SemesterStore: ObservableObject {
    @Published private(set) var deadlines: [CourseDeadline] = []
    @Published private(set) var classes: [ClassMeeting] = []

    private struct Snapshot: Codable {
        var deadlines: [CourseDeadline]
        var classes: [ClassMeeting]
    }

    private let fileURL: URL?

    init(fileURL: URL? = SemesterStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("semester.json")
    }

    // MARK: Queries

    var courses: [String] {
        Array(Set(deadlines.map(\.course) + classes.map(\.course))).sorted()
    }

    func upcomingDeadlines(now: Date = Date()) -> [CourseDeadline] {
        let today = Calendar.current.startOfDay(for: now)
        return deadlines.filter { $0.due >= today }.sorted { $0.due < $1.due }
    }

    func deadline(id: UUID?) -> CourseDeadline? {
        guard let id else { return nil }
        return deadlines.first { $0.id == id }
    }

    /// Times blocked by class on a given day. The scheduler plans around these.
    func classIntervals(on day: Date) -> [DateInterval] {
        classes.compactMap { $0.interval(on: day) }
    }

    func classes(on day: Date) -> [(meeting: ClassMeeting, interval: DateInterval)] {
        classes.compactMap { m in m.interval(on: day).map { (m, $0) } }
            .sorted { $0.interval.start < $1.interval.start }
    }

    // MARK: Changes

    func add(deadlines new: [CourseDeadline], classes newClasses: [ClassMeeting]) {
        deadlines.append(contentsOf: new)
        for meeting in newClasses where !classes.contains(where: {
            $0.course == meeting.course && $0.weekdays == meeting.weekdays && $0.startMinutes == meeting.startMinutes
        }) {
            classes.append(meeting)
        }
        save()
    }

    func upsert(_ meeting: ClassMeeting) {
        if let i = classes.firstIndex(where: { $0.id == meeting.id }) { classes[i] = meeting } else { classes.append(meeting) }
        save()
    }

    func removeClass(id: UUID) {
        classes.removeAll { $0.id == id }
        save()
    }

    func removeDeadline(id: UUID) {
        deadlines.removeAll { $0.id == id }
        save()
    }

    func replaceAll(deadlines: [CourseDeadline], classes: [ClassMeeting]) {
        self.deadlines = deadlines
        self.classes = classes
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        deadlines = snapshot.deadlines
        classes = snapshot.classes
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(deadlines: deadlines, classes: classes))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // Prototype: a failed save keeps the in-memory semester for this session.
        }
    }
}
