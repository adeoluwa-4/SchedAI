import Foundation

enum TaskPriority: String, CaseIterable, Codable, Hashable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var sortRank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

enum TaskPlanState: String, CaseIterable, Codable, Hashable, Identifiable {
    case ready
    case later
    case skippedToday
    case blocked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .later: return "Later"
        case .skippedToday: return "Skipped Today"
        case .blocked: return "Blocked"
        }
    }

    var subtitle: String {
        switch self {
        case .ready: return "SchedAI can place this in your day"
        case .later: return "Keep it open and move it later"
        case .skippedToday: return "Keep it, but leave it out today"
        case .blocked: return "Do not schedule until unblocked"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "wand.and.stars"
        case .later: return "clock.arrow.circlepath"
        case .skippedToday: return "forward.end.fill"
        case .blocked: return "exclamationmark.octagon.fill"
        }
    }
}

enum TaskPlanDisplayState: String, Hashable {
    case unplanned
    case planned
    case pinned
    case later
    case skippedToday
    case blocked
    case done

    var displayName: String {
        switch self {
        case .unplanned: return "Unplanned"
        case .planned: return "Planned"
        case .pinned: return "Pinned"
        case .later: return "Later"
        case .skippedToday: return "Skipped Today"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .unplanned: return "calendar.badge.plus"
        case .planned: return "calendar.badge.clock"
        case .pinned: return "pin.fill"
        case .later: return "clock.arrow.circlepath"
        case .skippedToday: return "forward.end.fill"
        case .blocked: return "exclamationmark.octagon.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

enum UnfinishedTaskPolicy: String, CaseIterable, Codable, Hashable, Identifiable {
    case askMe
    case carryOver
    case autoClear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askMe: return "Ask Me"
        case .carryOver: return "Carry Over"
        case .autoClear: return "Auto-clear"
        }
    }

    var subtitle: String {
        switch self {
        case .askMe: return "Review missed tasks before removing them"
        case .carryOver: return "Move unfinished tasks to the next day"
        case .autoClear: return "Remove unfinished tasks overnight"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var priority: TaskPriority = .medium
    var estimatedMinutes: Int = 30

    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    var planState: TaskPlanState = .ready
    var planStateUpdatedAt: Date? = nil

    /// If true, the user (or NLP) explicitly chose the time and the scheduler should not move it.
    /// If false, the scheduler is free to place this task anywhere in the work window.
    var isPinned: Bool = false

    /// Optional day assignment for tasks that should be planned on a specific date,
    /// even when no explicit clock time is provided.
    var targetDay: Date? = nil

    var scheduledStart: Date? = nil
    var scheduledEnd: Date? = nil

    func isMissed(now: Date = Date()) -> Bool {
        guard !isCompleted, let end = scheduledEnd else { return false }
        return end < now
    }

    func canAutoSchedule(on day: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted else { return false }

        switch planState {
        case .ready, .later:
            return true
        case .blocked:
            return false
        case .skippedToday:
            guard let skippedAt = planStateUpdatedAt else { return false }
            return !calendar.isDate(day, inSameDayAs: skippedAt)
        }
    }

    func displayPlanState(on day: Date = Date(), calendar: Calendar = .current) -> TaskPlanDisplayState {
        if isCompleted { return .done }

        switch planState {
        case .blocked:
            return .blocked
        case .skippedToday:
            if let skippedAt = planStateUpdatedAt, calendar.isDate(day, inSameDayAs: skippedAt) {
                return .skippedToday
            }
        case .later:
            return .later
        case .ready:
            break
        }

        if isPinned, scheduledStart != nil { return .pinned }
        if scheduledStart != nil { return .planned }
        return .unplanned
    }

    init(
        id: UUID = UUID(),
        title: String,
        estimatedMinutes: Int = 30,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        planState: TaskPlanState = .ready,
        planStateUpdatedAt: Date? = nil,
        isPinned: Bool = false,
        targetDay: Date? = nil,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.planState = planState
        self.planStateUpdatedAt = planStateUpdatedAt
        self.isPinned = isPinned
        self.targetDay = targetDay
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case priority
        case estimatedMinutes
        case isCompleted
        case completedAt
        case createdAt
        case planState
        case planStateUpdatedAt
        case isPinned
        case targetDay
        case scheduledStart
        case scheduledEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        self.estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 30
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.planState = try container.decodeIfPresent(TaskPlanState.self, forKey: .planState) ?? .ready
        self.planStateUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .planStateUpdatedAt)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.targetDay = try container.decodeIfPresent(Date.self, forKey: .targetDay)
        self.scheduledStart = try container.decodeIfPresent(Date.self, forKey: .scheduledStart)
        self.scheduledEnd = try container.decodeIfPresent(Date.self, forKey: .scheduledEnd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(priority, forKey: .priority)
        try container.encode(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(planState, forKey: .planState)
        try container.encodeIfPresent(planStateUpdatedAt, forKey: .planStateUpdatedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(targetDay, forKey: .targetDay)
        try container.encodeIfPresent(scheduledStart, forKey: .scheduledStart)
        try container.encodeIfPresent(scheduledEnd, forKey: .scheduledEnd)
    }
}
