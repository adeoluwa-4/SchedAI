import Foundation

struct TaskDraft: Codable, Equatable {
    let title: String
    let estimatedMinutes: Int?
    let priority: String?
    let targetDayISO8601: String?
    let scheduledStartISO8601: String?
    let scheduledEndISO8601: String?
    let preferredStartISO8601: String?
    let preferredEndISO8601: String?
    let isPinned: Bool?
    let notes: String?
}

enum TaskParseSource: Equatable {
    case onDeviceAI
    case ai
    case offline

    var isAIEnhanced: Bool {
        self == .onDeviceAI || self == .ai
    }
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
        static let aiClientID = "aiClientID"
    }

    private enum BundleKey {
        static let aiParseEndpoint = "SCHEDAI_AI_PARSE_ENDPOINT"
    }

    private enum Limits {
        static let maxRemoteInputCharacters = 4000
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
        planningDate: Date = Date(),
        allowsHostedAI: Bool = false
    ) async -> TaskParseResult {
        await improveTasksWithAI(from: input, now: now, planningDate: planningDate, allowsHostedAI: allowsHostedAI)
    }

    static func parseTasksOffline(from input: String, now: Date = Date()) -> TaskParseResult {
        TaskParseResult(tasks: fallbackTasks(from: input, now: now), source: .offline, message: nil)
    }

    static func improveTasksWithAI(
        from input: String,
        now: Date = Date(),
        planningDate: Date = Date(),
        allowsHostedAI: Bool = false
    ) async -> TaskParseResult {
        let safeInput = remoteSafeInput(input)

        if let drafts = await OnDeviceTaskParser.extractTasks(
            from: safeInput,
            now: now,
            planningDate: planningDate,
            offlinePreview: []
        ) {
            let validationFallback = fallbackTasks(from: safeInput, now: now)
            let onDevice = normalizedAIItems(
                from: drafts,
                fallback: validationFallback,
                input: safeInput,
                now: now
            )
            if !onDevice.isEmpty {
                return TaskParseResult(
                    tasks: onDevice,
                    source: .onDeviceAI,
                    message: "Improved on device with Apple Intelligence."
                )
            }
        }

        let offline = fallbackTasks(from: safeInput, now: now)
        let offlineDrafts = drafts(from: offline)

        guard allowsHostedAI else {
            return TaskParseResult(
                tasks: offline,
                source: .offline,
                message: "Apple Intelligence is unavailable. Used offline parser."
            )
        }

        guard let endpoint = parseEndpoint else {
            return TaskParseResult(tasks: offline, source: .offline, message: nil)
        }

        do {
            let drafts = try await extractTasks(
                from: safeInput,
                endpoint: endpoint,
                now: now,
                planningDate: planningDate,
                offlinePreview: offlineDrafts
            )
            let remote = taskItems(from: drafts)
            guard !remote.isEmpty else {
                return TaskParseResult(tasks: offline, source: .offline, message: "AI parser returned no tasks. Used offline parser.")
            }
            return TaskParseResult(tasks: remote, source: .ai, message: nil)
        } catch {
            let message: String
            if let serviceError = error as? AIServiceError {
                switch serviceError {
                case .badResponse(403):
                    message = offline.isEmpty ? "AI access is disabled for this app right now." : "AI access is disabled for this app right now. Used offline parser."
                case .badResponse(429):
                    message = offline.isEmpty ? "AI is being used too quickly right now." : "AI is being used too quickly right now. Used offline parser."
                case .badResponse(503):
                    message = offline.isEmpty ? "AI is temporarily turned off." : "AI is temporarily turned off. Used offline parser."
                default:
                    message = offline.isEmpty ? "AI parser unavailable." : "AI parser unavailable. Used offline parser."
                }
            } else {
                message = offline.isEmpty ? "AI parser unavailable." : "AI parser unavailable. Used offline parser."
            }
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
            let preferredStart = parseDate(draft.preferredStartISO8601, calendar: calendar)
            let preferredEnd = parseDate(draft.preferredEndISO8601, calendar: calendar)
            let targetDay = scheduledStart.map { calendar.startOfDay(for: $0) }
                ?? preferredStart.map { calendar.startOfDay(for: $0) }
                ?? parseDate(draft.targetDayISO8601, calendar: calendar).map { calendar.startOfDay(for: $0) }

            return TaskItem(
                title: title,
                estimatedMinutes: estimatedMinutes,
                priority: priority(from: draft.priority),
                isPinned: scheduledStart != nil ? (draft.isPinned ?? true) : false,
                targetDay: targetDay,
                scheduledStart: scheduledStart,
                scheduledEnd: scheduledEnd,
                preferredStart: preferredStart,
                preferredEnd: preferredEnd
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
        request.setValue(clientID(), forHTTPHeaderField: "X-SchedAI-Client-ID")

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
                preferredStartISO8601: item.preferredStart.map { isoString($0) },
                preferredEndISO8601: item.preferredEnd.map { isoString($0) },
                isPinned: item.isPinned,
                notes: nil
            )
        }
    }

    private static func normalizedAIItems(
        from drafts: [TaskDraft],
        fallback: [TaskItem],
        input: String,
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        var items = taskItems(from: drafts, calendar: calendar)
        guard !items.isEmpty else { return [] }

        if items.count == fallback.count {
            for index in items.indices {
                let fallbackTask = fallback[index]

                if items[index].scheduledStart == nil,
                   let fallbackStart = fallbackTask.scheduledStart {
                    items[index].isPinned = fallbackTask.isPinned
                    items[index].targetDay = fallbackTask.targetDay
                    items[index].scheduledStart = fallbackStart
                    items[index].scheduledEnd = fallbackTask.scheduledEnd
                }

                if items[index].preferredStart == nil,
                   let fallbackPreferredStart = fallbackTask.preferredStart {
                    items[index].targetDay = fallbackTask.targetDay
                    items[index].preferredStart = fallbackPreferredStart
                    items[index].preferredEnd = fallbackTask.preferredEnd
                }

                if index < drafts.count,
                   drafts[index].estimatedMinutes == nil,
                   fallbackTask.estimatedMinutes != 30 {
                    items[index].estimatedMinutes = fallbackTask.estimatedMinutes
                }
            }
        }

        normalizeDatesWithoutExplicitDay(
            items: &items,
            input: input,
            now: now,
            calendar: calendar
        )
        return items
    }

    private static func normalizeDatesWithoutExplicitDay(
        items: inout [TaskItem],
        input: String,
        now: Date,
        calendar: Calendar
    ) {
        guard !OfflineNLP.hasExplicitDayReference(input, now: now) else { return }

        let hasExplicitMeridiem = input.range(
            of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b(?:noon|midnight)\b"#,
            options: .regularExpression
        ) != nil
        let today = calendar.startOfDay(for: now)

        for index in items.indices {
            guard let start = items[index].scheduledStart else { continue }

            let duration = items[index].scheduledEnd.map { max(5 * 60, $0.timeIntervalSince(start)) }
            let components = calendar.dateComponents([.hour, .minute], from: start)
            guard let hour = components.hour, let minute = components.minute else { continue }

            if !calendar.isDate(start, inSameDayAs: now),
               let todayCandidate = date(on: today, hour: hour, minute: minute, calendar: calendar),
               todayCandidate >= now {
                moveTask(&items[index], to: todayCandidate, duration: duration, calendar: calendar)
                continue
            }

            if !hasExplicitMeridiem,
               (1...11).contains(hour),
               let pmCandidate = date(on: today, hour: hour + 12, minute: minute, calendar: calendar),
               pmCandidate >= now {
                moveTask(&items[index], to: pmCandidate, duration: duration, calendar: calendar)
            }
        }
    }

    private static func moveTask(
        _ task: inout TaskItem,
        to start: Date,
        duration: TimeInterval?,
        calendar: Calendar
    ) {
        task.scheduledStart = start
        task.scheduledEnd = duration.map { start.addingTimeInterval($0) }
        task.targetDay = calendar.startOfDay(for: start)
        task.isPinned = true
    }

    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func cleanURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty
        else { return nil }

        if scheme == "https" { return url }

        #if DEBUG
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) {
            return url
        }
        #endif

        return nil
    }

    private static func remoteSafeInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= Limits.maxRemoteInputCharacters {
            return trimmed
        }
        return String(trimmed.prefix(Limits.maxRemoteInputCharacters))
    }

    private static func clientID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: DefaultsKey.aiClientID),
           isValidClientID(existing) {
            return existing
        }

        let generated = "schedai." + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(generated, forKey: DefaultsKey.aiClientID)
        return generated
    }

    private static func isValidClientID(_ value: String) -> Bool {
        let pattern = #"^schedai\.[a-z0-9]{32}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func dateOnlyString(_ date: Date) -> String {
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
