import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceTaskParser {
    static func extractTasks(
        from input: String,
        now: Date,
        planningDate: Date,
        offlinePreview: [TaskDraft]
    ) async -> [TaskDraft]? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await FoundationModelsTaskParser.extractTasks(
                from: trimmed,
                now: now,
                planningDate: planningDate,
                offlinePreview: offlinePreview
            )
        }
        #endif

        return nil
    }
}

private struct OnDeviceTaskEnvelope: Codable {
    let tasks: [TaskDraft]
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private enum FoundationModelsTaskParser {
    static func extractTasks(
        from input: String,
        now: Date,
        planningDate: Date,
        offlinePreview: [TaskDraft]
    ) async -> [TaskDraft]? {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(_):
            return nil
        @unknown default:
            return nil
        }

        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt(
                    input: input,
                    now: now,
                    planningDate: planningDate,
                    offlinePreview: offlinePreview
                )
            )
            let data = try jsonObjectData(from: response.content)
            let decoded = try JSONDecoder().decode(OnDeviceTaskEnvelope.self, from: data)
            return decoded.tasks
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(20)
                .map { $0 }
        } catch {
            return nil
        }
    }

    private static let instructions = """
    You extract personal scheduling tasks for SchedAI.
    Return only valid JSON. Do not return markdown, prose, comments, or code fences.
    Preserve the user's intended action. If the user says "remind me at 2:30 to schedule a talk", the title is "Schedule a talk", not "Talk".
    Never invent tasks, people, dates, or locations.
    Use null when a field is unknown.
    """

    private static func prompt(
        input: String,
        now: Date,
        planningDate: Date,
        offlinePreview: [TaskDraft]
    ) -> String {
        let offlineJSON = jsonString(OnDeviceTaskEnvelope(tasks: offlinePreview))
        return """
        Current time: \(AIService.isoString(now))
        Planning date: \(AIService.dateOnlyString(planningDate))
        Time zone: \(TimeZone.current.identifier)
        Locale: \(Locale.current.identifier)

        User input:
        \(input)

        Offline parser preview:
        \(offlineJSON)

        Return JSON matching exactly this shape:
        {
          "tasks": [
            {
              "title": "Clean task title",
              "estimatedMinutes": 30,
              "priority": "high|medium|low",
              "targetDayISO8601": "yyyy-MM-dd or null",
              "scheduledStartISO8601": "ISO-8601 date-time or null",
              "scheduledEndISO8601": "ISO-8601 date-time or null",
              "isPinned": true,
              "notes": null
            }
          ]
        }

        Rules:
        - Split multiple clear actions into multiple tasks.
        - If the user gives an explicit clock time, set scheduledStartISO8601 and scheduledEndISO8601.
        - If there is no explicit clock time, leave scheduledStartISO8601 and scheduledEndISO8601 null.
        - If a bare time like "2:30" is still ahead today, interpret it as today PM unless the user clearly meant AM.
        - If a bare time is already past today, use the next plausible future occurrence.
        - Use the offline preview for date math when it looks reasonable.
        - Default estimatedMinutes to 30 when unknown.
        - Default priority to medium when unknown.
        """
    }

    private static func jsonObjectData(from raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end
        else {
            throw AIServiceError.parseFailed
        }

        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.parseFailed
        }
        return data
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"tasks":[]}"#
        }
        return string
    }
}
#endif
