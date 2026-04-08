import Foundation

// Returned by the AI or mock
struct TaskDraft: Codable {
    let title: String
    let estimatedMinutes: Int
    let dueDateISO8601: String?   // optional ISO8601 string
    let priority: Int?            // 1=high,2=med,3=low
    let notes: String?
}

enum AIServiceError: Error { case badResponse, parseFailed }

struct AIService {

    // MARK: - Mock (works offline)
    static func mockExtractTasks(from input: String) -> [TaskDraft] {
        let parsed = OfflineNLP.parseSafely(input)
        if !parsed.isEmpty {
            let iso = ISO8601DateFormatter()
            return parsed.map { item in
                TaskDraft(
                    title: item.title,
                    estimatedMinutes: max(5, min(item.estimatedMinutes, 600)),
                    dueDateISO8601: item.scheduledStart.map { iso.string(from: $0) },
                    priority: nil,
                    notes: nil
                )
            }
        }

        let fallbackTitle = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackTitle.isEmpty else { return [] }
        return [TaskDraft(title: fallbackTitle.capitalized, estimatedMinutes: 30, dueDateISO8601: nil, priority: nil, notes: nil)]
    }

    // MARK: - Real call (optional)
    static func extractTasks(from input: String, apiKey: String) async throws -> [TaskDraft] {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Return ONLY JSON with this shape:
        {"tasks":[{"title":"string","estimatedMinutes":30,"dueDateISO8601":"ISO8601 or null","priority":2,"notes":"string or null"}]}
        Input: "\(input)"
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "input": prompt
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIServiceError.badResponse
        }

        // Responses API: { output: [{ content: [{ text: "..." }] }] }
        struct Root: Decodable {
            struct Item: Decodable {
                struct C: Decodable { let type: String?; let text: String? }
                let content: [C]?
            }
            let output: [Item]?
            var firstText: String? { output?.first?.content?.first(where: { $0.text != nil })?.text }
        }

        let root = try JSONDecoder().decode(Root.self, from: data)
        guard let jsonText = root.firstText else { throw AIServiceError.parseFailed }

        struct Wrapper: Decodable { let tasks: [TaskDraft] }
        guard let decoded = try? JSONDecoder().decode(Wrapper.self, from: Data(jsonText.utf8)) else {
            throw AIServiceError.parseFailed
        }
        return decoded.tasks
    }
}
