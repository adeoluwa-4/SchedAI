import Foundation
import SwiftUI

// MARK: - Temporary Stubs
// These stubs allow the app to compile and run while real implementations are missing.
// Remove this file when you add your real models and views.

#if false

// Priority levels used by TaskItem
public enum TaskPriority: String, Codable, CaseIterable {
    case high
    case medium
    case low
}

// Minimal task model used by TasksView and TaskRow
public struct TaskItem: Identifiable, Equatable, Codable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var scheduledStart: Date?
    public var scheduledEnd: Date?
    public var dueDate: Date?
    public var estimatedMinutes: Int
    public var priority: TaskPriority

    public init(id: UUID = UUID(),
                title: String,
                isCompleted: Bool = false,
                scheduledStart: Date? = nil,
                scheduledEnd: Date? = nil,
                dueDate: Date? = nil,
                estimatedMinutes: Int = 0,
                priority: TaskPriority = .medium) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.dueDate = dueDate
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
    }
}

// Placeholder detail view
public struct TaskDetailView: View {
    public let task: TaskItem
    public init(task: TaskItem) { self.task = task }
    public var body: some View {
        Form {
            Text(task.title).font(.title2)
            Toggle("Completed", isOn: .constant(task.isCompleted))
            if let s = task.scheduledStart, let e = task.scheduledEnd {
                Text("When: \(s.formatted(date: .omitted, time: .shortened)) – \(e.formatted(date: .omitted, time: .shortened))")
            }
            if task.estimatedMinutes > 0 {
                Text("Estimate: \(task.estimatedMinutes)m")
            }
            HStack {
                Text("Priority:")
                Text(task.priority.rawValue.capitalized)
            }
        }
        .navigationTitle("Task Details")
    }
}

// Simple NLP parser stub used by quick-add; returns empty until real parser exists
public enum OfflineNLP {
    public static func parse(_ text: String) -> [TaskItem] {
        // TODO: Replace with real parsing logic
        return []
    }
}

#endif

