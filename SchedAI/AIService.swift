import Foundation

struct TaskDraft: Codable, Equatable {
    let title: String
    let estimatedMinutes: Int?
    let priority: String?
    let targetDayISO8601: String?
    let scheduledStartISO8601: String?
    let scheduledEndISO8601: String?
    let isPinned: Bool?
    let notes: String?
}

enum TaskParseSource: Equatable {
    case ai
    case offline
}

struct TaskParseResult: Equatable {
    let tasks: [TaskItem]
    let source: TaskParseSource
    let message: String?
}

enum AIServiceError: Error, Equatable {
    case badResponse(Int)
    case parseFailed
}

struct AIService {
    private enum DefaultsKey {
        static let aiParseEndpoint = "aiParseEndpoint"
    }

    private enum BundleKey {
        static let aiParseEndpoint = "SCHEDAI_AI_PARSE_ENDPOINT"
    }

    private struct ParseTasksRequest: Encodable {
        let input: String
        let nowISO8601: String
        let planningDateISO8601: String
        let timeZone: String
        let locale: String
        let offlinePreview: [TaskDraft]
    }

    private struct ParseTasksResponse: Decodable {
        let tasks: [TaskDraft]
        let needsClarification: Bool?
        let clarificationQuestion: String?
    }

    // Vercel keeps OPENAI_API_KEY server-side. Override with UserDefaults or Info.plist for other deployments.
    static var parseEndpoint: URL? {
        if let override = UserDefaults.standard.string(forKey: DefaultsKey.aiParseEndpoint),
           let url = cleanURL(override) {
            return url
        }

        if let bundled = Bundle.main.object(forInfoDictionaryKey: BundleKey.aiParseEndpoint) as? String,
           let url = cleanURL(bundled) {
            return url
        }

        return URL(string: "https://schedai-snowy.vercel.app/api/parse-tasks")
    }

    static func parseTasks(
        from input: String,
        now: Date = Date(),
        planningDate: Date = Date()
    ) async -> TaskParseResult {
        await improveTasksWithAI(from: input, now: now, planningDate: planningDate)
    }

    static func parseTasksOffline(from input: String, now: Date = Date()) -> TaskParseResult {
        TaskParseResult(tasks: fallbackTasks(from: input, now: now), source: .offline, message: nil)
    }

    static func improveTasksWithAI(
        from input: String,
        now: Date = Date(),
        planningDate: Date = Date()
    ) async -> TaskParseResult {
        let offline = fallbackTasks(from: input, now: now)
        guard let endpoint = parseEndpoint else {
            return TaskParseResult(tasks: offline, source: .offline, message: nil)
        }

        do {
            let drafts = try await extractTasks(
                from: input,
                endpoint: endpoint,
                now: now,
                planningDate: planningDate,
                offlinePreview: drafts(from: offline)
            )
            let remote = taskItems(from: drafts)
            guard !remote.isEmpty else {
                return TaskParseResult(tasks: offline, source: .offline, message: "AI parser returned no tasks. Used offline parser.")
            }
            return TaskParseResult(tasks: remote, source: .ai, message: nil)
        } catch {
            let message = offline.isEmpty ? "AI parser unavailable." : "AI parser unavailable. Used offline parser."
            return TaskParseResult(tasks: offline, source: .offline, message: message)
        }
    }

    static func mockExtractTasks(from input: String) -> [TaskDraft] {
        drafts(from: fallbackTasks(from: input))
    }

    static func taskItems(from drafts: [TaskDraft], calendar: Calendar = .current) -> [TaskItem] {
        drafts.compactMap { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let estimatedMinutes = clamp(draft.estimatedMinutes ?? 30, lower: 5, upper: 600)
            let scheduledStart = parseDate(draft.scheduledStartISO8601, calendar: calendar)
            let scheduledEnd = parseDate(draft.scheduledEndISO8601, calendar: calendar)
                ?? scheduledStart.flatMap { calendar.date(byAdding: .minute, value: estimatedMinutes, to: $0) }
            let targetDay = scheduledStart.map { calendar.startOfDay(for: $0) }
                ?? parseDate(draft.targetDayISO8601, calendar: calendar).map { calendar.startOfDay(for: $0) }

            return TaskItem(
                title: title,
                estimatedMinutes: estimatedMinutes,
                priority: priority(from: draft.priority),
                isPinned: scheduledStart != nil ? (draft.isPinned ?? true) : false,
                targetDay: targetDay,
                scheduledStart: scheduledStart,
                scheduledEnd: scheduledEnd
            )
        }
    }

    private static func extractTasks(
        from input: String,
        endpoint: URL,
        now: Date,
        planningDate: Date,
        offlinePreview: [TaskDraft]
    ) async throws -> [TaskDraft] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ParseTasksRequest(
            input: input,
            nowISO8601: isoString(now),
            planningDateISO8601: isoString(planningDate),
            timeZone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            offlinePreview: offlinePreview
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.parseFailed }
        guard (200..<300).contains(http.statusCode) else { throw AIServiceError.badResponse(http.statusCode) }

        let decoded = try JSONDecoder().decode(ParseTasksResponse.self, from: data)
        return decoded.tasks
    }

    private static func fallbackTasks(from input: String, now: Date = Date()) -> [TaskItem] {
        let parsed = OfflineNLP.parseSafely(input, now: now)
        if !parsed.isEmpty { return parsed }

        let fallbackTitle = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackTitle.isEmpty else { return [] }
        return [TaskItem(title: fallbackTitle, estimatedMinutes: 30, priority: .medium)]
    }

    private static func drafts(from items: [TaskItem]) -> [TaskDraft] {
        items.map { item in
            TaskDraft(
                title: item.title,
                estimatedMinutes: item.estimatedMinutes,
                priority: item.priority.rawValue,
                targetDayISO8601: item.targetDay.map { dateOnlyString($0) },
                scheduledStartISO8601: item.scheduledStart.map { isoString($0) },
                scheduledEndISO8601: item.scheduledEnd.map { isoString($0) },
                isPinned: item.isPinned,
                notes: nil
            )
        }
    }

    private static func cleanURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func priority(from raw: String?) -> TaskPriority {
        switch raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "high", "urgent", "1":
            return .high
        case "low", "3":
            return .low
        default:
            return .medium
        }
    }

    private static func parseDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let dateOnly = DateFormatter()
        dateOnly.calendar = calendar
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = calendar.timeZone
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: trimmed)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dateOnlyString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
