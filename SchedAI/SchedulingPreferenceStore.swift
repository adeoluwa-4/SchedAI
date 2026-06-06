import Foundation

struct SchedulingPreferenceStore {
    private enum DefaultsKey {
        static let learnedWindows = "learnedTimingWindows"
    }

    private struct LearnedWindow: Codable {
        var phraseKey: String
        var startMinuteOfDay: Int
        var endMinuteOfDay: Int
        var sampleCount: Int
        var updatedAt: Date
    }

    private enum PhraseKey: String, CaseIterable {
        case laterToday
        case afternoon
        case evening
        case tonight

        var displayName: String {
            switch self {
            case .laterToday: return "later today"
            case .afternoon: return "afternoon"
            case .evening: return "evening"
            case .tonight: return "tonight"
            }
        }
    }

    static func learnedWindow(for text: String, targetDay: Date?, now: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard let key = phraseKey(in: text),
              let learned = storedWindows()[key.rawValue] else {
            return nil
        }

        let day = calendar.startOfDay(for: targetDay ?? now)
        guard var start = date(on: day, minuteOfDay: learned.startMinuteOfDay, calendar: calendar),
              var end = date(on: day, minuteOfDay: learned.endMinuteOfDay, calendar: calendar) else {
            return nil
        }

        if calendar.isDate(day, inSameDayAs: now), start <= now {
            start = roundUp(calendar.date(byAdding: .minute, value: 60, to: now) ?? now, toMinutes: 5, calendar: calendar)
        }
        if end <= start {
            end = calendar.date(byAdding: .hour, value: 2, to: start) ?? start.addingTimeInterval(7200)
        }
        return (start, end)
    }

    static func promptContext(for text: String, now: Date, calendar: Calendar = .current) -> String? {
        guard let key = phraseKey(in: text),
              let learned = storedWindows()[key.rawValue],
              let start = date(on: now, minuteOfDay: learned.startMinuteOfDay, calendar: calendar),
              let end = date(on: now, minuteOfDay: learned.endMinuteOfDay, calendar: calendar) else {
            return nil
        }

        return """
        Local user timing preference:
        - When this user says "\(key.displayName)", they usually mean \(timeString(start))-\(timeString(end)).
        - Use that as a preferredStartISO8601/preferredEndISO8601 window, not a pinned exact scheduledStartISO8601, unless the user gives an explicit clock time.
        """
    }

    static func recordCorrection(from text: String, correctedStart: Date, durationMinutes: Int, calendar: Calendar = .current) {
        guard let key = phraseKey(in: text) else { return }

        let correctedMinute = minuteOfDay(correctedStart, calendar: calendar)
        let learnedStart = clamp(roundDown(correctedMinute, to: 15), lower: 0, upper: 23 * 60 + 45)
        let learnedEnd = clamp(roundUp(correctedMinute + max(120, durationMinutes + 90), to: 15), lower: learnedStart + 30, upper: 24 * 60 - 1)

        var windows = storedWindows()
        if var existing = windows[key.rawValue] {
            let nextCount = min(existing.sampleCount + 1, 20)
            existing.startMinuteOfDay = weightedAverage(existing.startMinuteOfDay, learnedStart, oldCount: existing.sampleCount)
            existing.endMinuteOfDay = weightedAverage(existing.endMinuteOfDay, learnedEnd, oldCount: existing.sampleCount)
            existing.sampleCount = nextCount
            existing.updatedAt = Date()
            windows[key.rawValue] = existing
        } else {
            windows[key.rawValue] = LearnedWindow(
                phraseKey: key.rawValue,
                startMinuteOfDay: learnedStart,
                endMinuteOfDay: learnedEnd,
                sampleCount: 1,
                updatedAt: Date()
            )
        }
        save(windows)
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.learnedWindows)
    }

    private static func phraseKey(in text: String) -> PhraseKey? {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if normalized.range(of: #"(?i)\b(tonight|before bed|before sleep)\b"#, options: .regularExpression) != nil {
            return .tonight
        }
        if normalized.range(of: #"(?i)\b(this evening|evening)\b"#, options: .regularExpression) != nil {
            return .evening
        }
        if normalized.range(of: #"(?i)\b(this afternoon|afternoon)\b"#, options: .regularExpression) != nil {
            return .afternoon
        }
        if normalized.range(of: #"(?i)\b(later today|later)\b"#, options: .regularExpression) != nil {
            return .laterToday
        }
        return nil
    }

    private static func storedWindows() -> [String: LearnedWindow] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.learnedWindows),
              let decoded = try? JSONDecoder().decode([String: LearnedWindow].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save(_ windows: [String: LearnedWindow]) {
        guard let data = try? JSONEncoder().encode(windows) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.learnedWindows)
    }

    private static func date(on day: Date, minuteOfDay: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        components.second = 0
        return calendar.date(from: components)
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func roundDown(_ value: Int, to step: Int) -> Int {
        (value / step) * step
    }

    private static func roundUp(_ value: Int, to step: Int) -> Int {
        ((value + step - 1) / step) * step
    }

    private static func roundUp(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        let roundedMinute = ((minute + step - 1) / step) * step

        var adjusted = components
        adjusted.minute = roundedMinute % 60
        adjusted.second = 0
        let hourCarry = roundedMinute / 60
        guard let base = calendar.date(from: adjusted) else { return date }
        return hourCarry > 0 ? (calendar.date(byAdding: .hour, value: hourCarry, to: base) ?? base) : base
    }

    private static func weightedAverage(_ old: Int, _ new: Int, oldCount: Int) -> Int {
        ((old * oldCount) + new) / max(1, oldCount + 1)
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
