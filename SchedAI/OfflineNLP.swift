//
//  OfflineNLP.swift
//  SchedAI
//
//  Heuristic, fully-offline natural language parser.
//  Focus: robust time inference (AM/PM), time ranges, spelled-out times, and realistic defaults.
//

import Foundation

struct OfflineNLP {

    // MARK: - Cached regex + lookups

    private enum Cache {
        static let numberWordMap: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
        ]

        // Recurrence
        static let everyDayRegex = try! NSRegularExpression(pattern: #"(?i)\bevery\s+day\b"#)
        static let everyWeekdayRegex = try! NSRegularExpression(pattern: #"(?i)\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#)
        static let monthlyRegexes: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: #"(?i)\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)?\s+of\s+every\s+month\b"#),
            try! NSRegularExpression(pattern: #"(?i)\bevery\s+month(?:\s+on\s+the\s+(\d{1,2})(?:st|nd|rd|th)?)?\b"#),
            try! NSRegularExpression(pattern: #"(?i)\bmonthly(?:\s+on\s+the\s+(\d{1,2})(?:st|nd|rd|th)?)?\b"#)
        ]

        // Spoken clock phrases
        static let halfPastRegex = try! NSRegularExpression(pattern: #"(?i)\bhalf\s+past\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let quarterPastRegex = try! NSRegularExpression(pattern: #"(?i)\bquarter\s+past\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let quarterToRegex = try! NSRegularExpression(pattern: #"(?i)\bquarter\s+to\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)

        // Number words in time/duration contexts
        static let timeContextRegex = try! NSRegularExpression(pattern: #"(?i)\b(at|around|by|from|to|until|till|between)\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let durationWordRegex = try! NSRegularExpression(pattern: #"(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(hours?|hrs?|h|minutes?|mins?|m)\b"#)

        // Chunking
        static let primaryChunkDelimiterRegex = try! NSRegularExpression(
            pattern: #"(?i)\s*(?:;|•|,|\s-\s|\band\s+then\b|\bthen\b|\bafter\s+that\b|\bafterwards\b|\blater\b)\s*"#
        )
        static let betweenAndRegex = try! NSRegularExpression(pattern: #"(?i)\bbetween\b.*\band\b"#)
        static let andDelimiterRegex = try! NSRegularExpression(pattern: #"(?i)\s+and\s+"#)
        static let timeMarkerSplitRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at|by|around)\s+(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?|\d{3,4}|noon|midnight)\b"#)
        static let leadingDurationRegex = try! NSRegularExpression(pattern: #"(?i)^\s*(?:for\s+)?\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|mins?|minutes?)\b"#)
        static let fusedVerbs: [String] = [
            "shower", "eat", "study", "walk", "run", "workout", "gym",
            "clean", "laundry", "cook", "drive", "commute",
            "call", "text", "email",
            "practice", "review", "read", "write",
            "pack", "prep",
            "nap", "sleep",
            "play", "watch",
            "shop", "grocery", "snack",
            "meeting",
            "unpack"
        ]
        static let fusedVerbRegex: NSRegularExpression = {
            let pattern = "(?i)\\b(" + fusedVerbs.joined(separator: "|") + ")\\b"
            return try! NSRegularExpression(pattern: pattern)
        }()

        // Base day extraction
        static let monthDayRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,\s*|\s+)?(\d{4})?\b"#)
        static let numericDateRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b"#)
        static let dayOfWeekRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?((?:next|this|coming)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#)
        static let relativeDayRegex = try! NSRegularExpression(pattern: #"(?i)\bin\s+(\d+)\s*(day|days|week|weeks)\b"#)
        static let relativeFromNowRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(day|days|week|weeks)\s+from\s+now\b"#)
        static let weekdayOrdinalRegex = try! NSRegularExpression(pattern: #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+the\s+(\d{1,2})(?:st|nd|rd|th)?\b"#)
        static let tomorrowVariantsRegex = try! NSRegularExpression(pattern: #"(?i)\b(tomorrow|tommorow|tomorow|tmrw|tommorrow|tommporw)\b"#)
        static let nextMonthRegex = try! NSRegularExpression(pattern: #"(?i)\bnext\s+month\b"#)

        // Relative time
        static let nextWindowRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:in|within|over)\s+(?:the\s+)?next\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#)
        static let nextWindowShortRegex = try! NSRegularExpression(pattern: #"(?i)\bnext\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#)
        static let relativeTimeRegex = try! NSRegularExpression(pattern: #"(?i)\bin\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#)

        // Time ranges / single times
        static let timeRangeRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:(from|between)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:to|and|-)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#)
        static let untilRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#)
        static let time24Regex = try! NSRegularExpression(pattern: #"(?i)\b([01]?\d|2[0-3])\s*:\s*([0-5]\d)\b"#)
        static let time12Regex = try! NSRegularExpression(pattern: #"(?i)\b(1[0-2]|0?[1-9])(?::\s*([0-5]\d))?\s*(am|pm)\b"#)
        static let timeColonNoMeridiemRegex = try! NSRegularExpression(pattern: #"(?i)\b(1[0-2]|0?[1-9])\s*:\s*([0-5]\d)\b"#)
        static let timeCompactRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at|around|by|from|starting|start)\s*(\d{3,4})\b"#)
        static let timeBareHourRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at|around|by)\s*(\d{1,2})\b(?!\s*(?:h|hr|hrs|hour|hours|min|mins|minute|minutes))"#
        )
        static let midnightRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at\s+|by\s+|around\s+)?midnight\b"#)
        static let noonRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at\s+|by\s+|around\s+)?noon\b"#)
        static let eodRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:by\s+)?(?:eod|end\s+of\s+day)\b"#)

        // Duration parsing
        static let durationForRegex = try! NSRegularExpression(pattern: #"(?i)\bfor\s+(\d+(?:\.\d+)?)\s*(h|hrs?|hours?|m|mins?|minutes?)\b"#)
        static let durationHourHalfRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(h|hrs?|hours?)\b"#)
        static let durationComboRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(h|hrs?|hours?)\s+(\d+)\s*(m|mins?|minutes?)\b"#)
        static let durationMinutesRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(m|mins?|minutes?)\b"#)
        static let durationHoursRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(h|hrs?|hours?)\b"#)
    }

    // MARK: - Public entry point

    static func parse(_ rawText: String, now: Date = Date()) -> [TaskItem] {
        if shouldUseStepPipeline(rawText) {
            let planned = parseWithStepPipeline(rawText, now: now)
            if !planned.isEmpty {
                if rawText.contains(","), planned.count <= 1 {
                    let fallback = parseInternal(rawText, now: now, minConfidence: .medium)
                    if fallback.count > planned.count { return fallback }
                }
                return planned
            }
        }
        return parseInternal(rawText, now: now, minConfidence: .medium)
    }

    /// Safer parsing: only schedules times when confidence is high.
    static func parseSafely(_ rawText: String, now: Date = Date()) -> [TaskItem] {
        if shouldUseStepPipeline(rawText) {
            let planned = parseWithStepPipeline(rawText, now: now)
            if !planned.isEmpty {
                var safePlanned = planned
                applySafeAmbiguityGuard(to: &safePlanned, rawText: rawText)
                if rawText.contains(","), safePlanned.count <= 1 {
                    let fallback = parseInternal(rawText, now: now, minConfidence: .high)
                    if fallback.count > safePlanned.count { return fallback }
                }
                return safePlanned
            }
        }
        return parseInternal(rawText, now: now, minConfidence: .high)
    }

    private static func parseInternal(_ rawText: String, now: Date, minConfidence: TimeConfidence) -> [TaskItem] {
        let text = normalize(rawText)
        let chunks = splitIntoChunks(text)

        var tasks: [TaskItem] = []

        for rawChunk in chunks {
            let recResult = detectRecurrence(in: rawChunk)
            let chunk = recResult.cleaned

            if let base = parseChunk(chunk, now: now, minConfidence: minConfidence) {
                if let rec = recResult.recurrence {
                    let copies = duplicate(task: base, for: rec, reference: now)
                    tasks.append(contentsOf: copies)
                } else {
                    tasks.append(base)
                }
            }
        }

        return tasks
    }

    // MARK: - Step-based pipeline

    private enum StepRegex {
        static let connectorRegex = try! NSRegularExpression(
            pattern: #"(?i)\s*(?:\band\s+then\b|\bafter\s+that\b|\bthen\b|\bnext\b(?!\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|day|days|week|month|year|\d+\s*(?:m|min|mins?|minutes?|h|hr|hrs?|hours?)))|\band\b)\s*"#
        )
        static let durationRegex = try! NSRegularExpression(
            pattern: #"(?i)\bfor\s+(?:a\s+)?(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?)\b"#
        )
        static let rangeRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:till|to|-)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        )
        static let explicitTimeRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:at|by)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        )
        static let bareMeridiemRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))\s*(am|pm)\b"#
        )
        static let durationThenActionRangeRegex = try! NSRegularExpression(
            pattern: #"(?i)^(.*?\bfor\s+\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|min|mins|minutes?)\b)\s+([a-z].*\b\d{1,2}\s*(?:till|to|-)\s*\d{1,2}\b.*)$"#
        )
        static let rangeAndDurationCleanupRegex = try! NSRegularExpression(
            pattern: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:till|to|-)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b|\b(?:at|by)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b|\b(?:a\s+)?\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|min|mins|minutes?)\b|\b(?:midnight|noon)\b"#
        )
        static let relativeWindowRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:in|within|over)\s+(?:the\s+)?next\s+(\d+(?:\.\d+)?)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#
        )
        static let relativeOffsetRegex = try! NSRegularExpression(
            pattern: #"(?i)\bin\s+(\d+(?:\.\d+)?)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#
        )
        static let relativeDatePhraseRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:today|tomorrow|tommorow|tomorow|tommorrow|tmrw|tommporw|next\s+month|next\s+week|next\s+year|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|this\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|coming\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\d+\s*(?:day|days|week|weeks)\s+from\s+now|in\s+\d+\s*(?:day|days|week|weeks)|(?:on\s+)?(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?(?:,\s*\d{4})?|(?:on\s+)?\d{1,2}\/\d{1,2}(?:\/\d{2,4})?|(?:on\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+the\s+\d{1,2}(?:st|nd|rd|th)?)\b"#
        )
    }

    static func normalizeInput(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: "\t", with: " ")
        s = s.replacingOccurrences(of: #"(?i)\ba\.?\s*m\.?\b"#, with: "am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bp\.?\s*m\.?\b"#, with: "pm", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bturn\s+nike\b"#, with: "tonight", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btonike\b"#, with: "tonight", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bto\s+night\b"#, with: "tonight", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bweday\b"#, with: "wednesday", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bmotnh\b"#, with: "month", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bnoe\b"#, with: "now", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btommorow\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btomorow\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btommorrow\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btommporw\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\band\s+after\s+that\b"#, with: " after that ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bmidnight\b"#, with: "12 am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bnoon\b"#, with: "12 pm", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?i)\bbetween\s+(\d{1,2}(?::\d{2})?)\s+and\s+(\d{1,2}(?::\d{2})?)\b"#,
            with: "between $1 to $2",
            options: .regularExpression
        )

        let numberWords: [String: String] = [
            "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
            "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
            "eleven": "11", "twelve": "12"
        ]
        for (word, digit) in numberWords {
            s = s.replacingOccurrences(of: #"(?i)\b\#(word)\b"#, with: digit, options: .regularExpression)
        }

        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitTasks(_ text: String) -> [String] {
        let normalized = normalizeInput(text)
        guard !normalized.isEmpty else { return [] }

        let ns = normalized as NSString
        let replaced = StepRegex.connectorRegex.stringByReplacingMatches(
            in: normalized,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "|"
        )

        var chunks = replaced
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        chunks = chunks.flatMap { splitDurationThenRangeChunk($0) }
        chunks = chunks.flatMap { splitOnMultipleTimeMarkers($0) }
        chunks = chunks.flatMap { splitOnPhrases($0) }

        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func extractTimes(from text: String) -> (start: Date?, end: Date?, duration: Int?) {
        extractTimes(from: text, referenceDate: Date(), previousTaskStart: nil)
    }

    private static func shouldUseStepPipeline(_ rawText: String) -> Bool {
        rawText.range(
            of: #"(?i)\b(and|then|after\s+that|next)\b|\b\d{1,2}(?::\d{2})?\s*(?:till|to|-)\s*\d{1,2}(?::\d{2})?\b|\bmidnight\b|\bnoon\b|\b(?:breakfast|lunch|dinner|supper|bed|sleep|study|homework|laundry|gym|workout|play)\b.*\bat\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseWithStepPipeline(_ rawText: String, now: Date) -> [TaskItem] {
        let chunks = splitTasks(rawText)
        guard !chunks.isEmpty else { return [] }

        var tasks: [TaskItem] = []
        var previousTaskStart: Date? = nil

        for chunk in chunks {
            let recResult = detectRecurrence(in: chunk)
            let parsedChunk = recResult.cleaned

            let timing = extractTimes(from: parsedChunk, referenceDate: now, previousTaskStart: previousTaskStart)
            let priorityResult = extractPriority(from: parsedChunk)
            let title = extractStepTitle(from: priorityResult.cleaned)
            guard !title.isEmpty else { continue }

            let estimated = max(5, timing.duration ?? 30)
            let start = timing.start
            var end = timing.end

            if let start, end == nil {
                end = Calendar.current.date(byAdding: .minute, value: estimated, to: start)
            }

            if let start {
                previousTaskStart = start
            }

            let task = TaskItem(
                title: title,
                estimatedMinutes: estimated,
                priority: priorityResult.priority,
                isPinned: start != nil,
                scheduledStart: start,
                scheduledEnd: end
            )

            if let rec = recResult.recurrence {
                let copies = duplicate(task: task, for: rec, reference: now)
                tasks.append(contentsOf: copies)
            } else {
                tasks.append(task)
            }
        }

        enforceNonOverlappingSchedule(&tasks)
        return tasks
    }

    private static func splitDurationThenRangeChunk(_ chunk: String) -> [String] {
        let s = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = StepRegex.durationThenActionRangeRegex.firstMatch(in: s, range: range),
              let leftRange = Range(match.range(at: 1), in: s),
              let rightRange = Range(match.range(at: 2), in: s) else {
            return [s]
        }

        let left = String(s[leftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(s[rightRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return [s] }
        return [left, right]
    }

    private static func extractTimes(from text: String, referenceDate: Date, previousTaskStart: Date?) -> (start: Date?, end: Date?, duration: Int?) {
        let normalized = normalizeInput(text)
        let calendar = Calendar.current
        let dayResult = extractBaseDay(from: normalized, now: referenceDate)
        let working = dayResult.cleaned
        let hasExplicitDay = dayResult.hasExplicitDay

        let ns = working as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        var durationMinutes: Int? = nil
        if let durationMatch = StepRegex.durationRegex.firstMatch(in: working, range: fullRange),
           let valueRange = Range(durationMatch.range(at: 1), in: working),
           let unitRange = Range(durationMatch.range(at: 2), in: working),
           let value = Double(working[valueRange]) {
            let unit = working[unitRange].lowercased()
            let isHours = unit.hasPrefix("h") || unit.hasPrefix("hr") || unit.hasPrefix("hour")
            durationMinutes = isHours ? Int((value * 60).rounded()) : Int(value.rounded())
        }

        let baseAnchor = dayResult.baseDay ?? previousTaskStart ?? referenceDate
        let baseDay = calendar.startOfDay(for: baseAnchor)

        func buildDate(hour24: Int, minute: Int) -> Date? {
            var comps = calendar.dateComponents([.year, .month, .day], from: baseDay)
            comps.hour = max(0, min(23, hour24))
            comps.minute = max(0, min(59, minute))
            comps.second = 0
            return calendar.date(from: comps)
        }

        if let relWindow = StepRegex.relativeWindowRegex.firstMatch(in: working, range: fullRange),
           let valueRange = Range(relWindow.range(at: 1), in: working),
           let unitRange = Range(relWindow.range(at: 2), in: working),
           let value = Double(working[valueRange]), value > 0 {
            let unit = working[unitRange].lowercased()
            let minutes = (unit.hasPrefix("h") || unit.hasPrefix("hr") || unit.hasPrefix("hour"))
                ? Int((value * 60).rounded())
                : Int(value.rounded())
            let start = roundUp(referenceDate, toMinutes: 5, calendar: calendar)
            let end = calendar.date(byAdding: .minute, value: max(5, minutes), to: start)
            return (start, end, max(5, minutes))
        }

        if let relOffset = StepRegex.relativeOffsetRegex.firstMatch(in: working, range: fullRange),
           let valueRange = Range(relOffset.range(at: 1), in: working),
           let unitRange = Range(relOffset.range(at: 2), in: working),
           let value = Double(working[valueRange]), value > 0 {
            let unit = working[unitRange].lowercased()
            let minutes = (unit.hasPrefix("h") || unit.hasPrefix("hr") || unit.hasPrefix("hour"))
                ? Int((value * 60).rounded())
                : Int(value.rounded())
            let start = calendar.date(byAdding: .minute, value: max(1, minutes), to: referenceDate)
            return (start, nil, durationMinutes)
        }

        if let rangeMatch = StepRegex.rangeRegex.firstMatch(in: working, range: fullRange) {
            let sh = Int(ns.substring(with: rangeMatch.range(at: 1))) ?? 0
            let sm = (rangeMatch.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: rangeMatch.range(at: 2))) ?? 0) : 0
            let sap = (rangeMatch.range(at: 3).location != NSNotFound) ? ns.substring(with: rangeMatch.range(at: 3)).lowercased() : nil

            let eh = Int(ns.substring(with: rangeMatch.range(at: 4))) ?? 0
            let em = (rangeMatch.range(at: 5).location != NSNotFound) ? (Int(ns.substring(with: rangeMatch.range(at: 5))) ?? 0) : 0
            let eap = (rangeMatch.range(at: 6).location != NSNotFound) ? ns.substring(with: rangeMatch.range(at: 6)).lowercased() : nil

            let startHour = resolveHour(rawHour: sh, ampm: sap, context: working, previousTaskStart: previousTaskStart)
            var endHour = resolveHour(rawHour: eh, ampm: eap ?? sap, context: working, previousTaskStart: previousTaskStart)
            if eap == nil, sap == nil, startHour >= 12, eh <= 11 {
                endHour = eh + 12
            }

            var start = buildDate(hour24: startHour, minute: sm)
            var end = buildDate(hour24: endHour, minute: em)

            if let s = start, let e = end, e <= s {
                end = calendar.date(byAdding: .hour, value: 12, to: e)
                if let e2 = end, e2 <= s {
                    end = calendar.date(byAdding: .day, value: 1, to: e2)
                }
            }

            if !hasExplicitDay, let prev = previousTaskStart, let s = start, s <= prev {
                start = calendar.date(byAdding: .day, value: 1, to: s)
                if let e = end { end = calendar.date(byAdding: .day, value: 1, to: e) }
            }

            let computedDuration: Int?
            if let s = start, let e = end {
                computedDuration = max(5, Int(e.timeIntervalSince(s) / 60))
            } else {
                computedDuration = nil
            }
            return (start, end, durationMinutes ?? computedDuration)
        }

        var start: Date? = nil

        if let explicit = StepRegex.explicitTimeRegex.firstMatch(in: working, range: fullRange) {
            let h = Int(ns.substring(with: explicit.range(at: 1))) ?? 0
            let m = (explicit.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: explicit.range(at: 2))) ?? 0) : 0
            let ap = (explicit.range(at: 3).location != NSNotFound) ? ns.substring(with: explicit.range(at: 3)).lowercased() : nil
            let hour24 = resolveHour(rawHour: h, ampm: ap, context: working, previousTaskStart: previousTaskStart)
            start = buildDate(hour24: hour24, minute: m)
        } else if let bare = StepRegex.bareMeridiemRegex.firstMatch(in: working, range: fullRange) {
            let h = Int(ns.substring(with: bare.range(at: 1))) ?? 0
            let m = (bare.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: bare.range(at: 2))) ?? 0) : 0
            let ap = ns.substring(with: bare.range(at: 3)).lowercased()
            let hour24 = resolveHour(rawHour: h, ampm: ap, context: working, previousTaskStart: previousTaskStart)
            start = buildDate(hour24: hour24, minute: m)
        }

        let lower = working.lowercased()
        let beforeBedContext = lower.contains("before bed") || lower.contains("before sleep")
        if start == nil {
            if lower.contains("breakfast") {
                start = buildDate(hour24: 8, minute: 0)
            } else if lower.contains("lunch") {
                start = buildDate(hour24: 12, minute: 0)
            } else if lower.contains("dinner") {
                start = buildDate(hour24: 19, minute: 0)
            } else if !beforeBedContext,
                      lower.range(of: #"\b(?:go\s+to\s+bed|bedtime|go\s+to\s+sleep|go\s+sleep)\b"#, options: .regularExpression) != nil {
                start = buildDate(hour24: 0, minute: 0)
            }
        }

        if !hasExplicitDay, let prev = previousTaskStart, let s = start, s <= prev {
            start = calendar.date(byAdding: .day, value: 1, to: s)
        }

        let end: Date?
        if let s = start, let durationMinutes {
            end = calendar.date(byAdding: .minute, value: max(5, durationMinutes), to: s)
        } else {
            end = nil
        }

        return (start, end, durationMinutes)
    }

    private static func resolveHour(rawHour: Int, ampm: String?, context: String, previousTaskStart: Date?) -> Int {
        let hour = max(1, min(12, rawHour))
        if let ampm {
            if ampm == "am" { return (hour == 12) ? 0 : hour }
            return (hour == 12) ? 12 : hour + 12
        }

        let lower = context.lowercased()
        if lower.contains("breakfast") || lower.contains("morning") {
            return (hour == 12) ? 8 : hour
        }
        if lower.contains("lunch") || lower.contains("afternoon") {
            return (hour == 12) ? 12 : ((hour <= 6) ? hour + 12 : hour)
        }
        if lower.contains("dinner") || lower.contains("supper") {
            return (hour == 12) ? 19 : ((hour <= 11) ? hour + 12 : hour)
        }
        if lower.contains("evening") || lower.contains("tonight") || lower.contains("night") {
            return (hour == 12) ? 12 : hour + 12
        }
        if lower.contains("bed") || lower.contains("sleep") {
            if hour == 12 { return 0 }
            if hour <= 5 { return hour }
            return hour + 12
        }

        let prevHour = previousTaskStart.map { Calendar.current.component(.hour, from: $0) }
        if let prevHour, prevHour >= 12, hour <= 11 { return (hour == 12) ? 12 : hour + 12 }

        // If a morning task was already parsed, later unspecified times are usually afternoon/evening.
        if let prevHour, prevHour < 12, hour <= prevHour, hour <= 11 {
            return (hour == 12) ? 12 : hour + 12
        }

        // Ambiguous productivity/social actions default to PM for low hours (e.g. "study at 4").
        let likelyPmWords = [
            "study", "homework", "assignment", "work", "laundry", "gym", "workout",
            "exercise", "practice", "review", "meeting", "class", "play", "game",
            "call", "dinner", "lunch", "eat"
        ]
        if hour <= 8, likelyPmWords.contains(where: lower.contains) {
            return hour + 12
        }

        return hour
    }

    private static func extractStepTitle(from text: String) -> String {
        let normalized = normalizeInput(text)
        let ns = normalized as NSString
        var stripped = StepRegex.rangeAndDurationCleanupRegex.stringByReplacingMatches(
            in: normalized,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: " "
        )
        let strippedNS = stripped as NSString
        stripped = StepRegex.relativeDatePhraseRegex.stringByReplacingMatches(
            in: stripped,
            range: NSRange(location: 0, length: strippedNS.length),
            withTemplate: " "
        )
        stripped = stripped.replacingOccurrences(of: #"(?i)\bbefore\s+(?:bed|sleep)\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bbetween\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bin\s+the\s+next\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bfor\s+walk\b"#, with: "for a walk", options: .regularExpression)
        return cleanedTitle(from: stripped)
    }

    private static func enforceNonOverlappingSchedule(_ tasks: inout [TaskItem]) {
        guard tasks.count > 1 else {
            if let start = tasks.first?.scheduledStart, tasks.first?.scheduledEnd == nil {
                tasks[0].scheduledEnd = Calendar.current.date(byAdding: .minute, value: max(5, tasks[0].estimatedMinutes), to: start)
            }
            return
        }

        let calendar = Calendar.current

        for i in tasks.indices {
            if let start = tasks[i].scheduledStart, tasks[i].scheduledEnd == nil {
                tasks[i].scheduledEnd = calendar.date(byAdding: .minute, value: max(5, tasks[i].estimatedMinutes), to: start)
            }
        }

        for i in 1..<tasks.count {
            guard let currentStart = tasks[i].scheduledStart else { continue }

            let prevStart = tasks[i - 1].scheduledStart
            let prevEnd = tasks[i - 1].scheduledEnd
                ?? (prevStart.flatMap { calendar.date(byAdding: .minute, value: max(5, tasks[i - 1].estimatedMinutes), to: $0) })
            guard let prevEnd else { continue }

            if currentStart < prevEnd {
                tasks[i].scheduledStart = prevEnd
                tasks[i].scheduledEnd = calendar.date(
                    byAdding: .minute,
                    value: max(5, tasks[i].estimatedMinutes),
                    to: prevEnd
                )
            }
        }
    }

    /// parseSafely still uses step parsing for multi-task robustness.
    /// This guard strips obviously ambiguous single bare-hour times like "study at 3".
    private static func applySafeAmbiguityGuard(to tasks: inout [TaskItem], rawText: String) {
        guard tasks.count == 1, tasks[0].scheduledStart != nil else { return }
        let text = normalizeInput(rawText)

        let hasBareHour = text.range(
            of: #"\b(?:at|by|around)\s*\d{1,2}\b(?!\s*(?:am|pm|:\d{2}))"#,
            options: .regularExpression
        ) != nil
        guard hasBareHour else { return }

        let hasStrongContext = text.range(
            of: #"\b(?:breakfast|lunch|dinner|supper|bed|sleep|midnight|noon|morning|afternoon|evening|tonight|today|tomorrow|in\s+\d+\s*(?:day|days|week|weeks)|\d+\s*(?:day|days|week|weeks)\s+from\s+now|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|year)|this\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|coming\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\/\d{1,2}\b|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#,
            options: .regularExpression
        ) != nil

        if !hasStrongContext {
            tasks[0].scheduledStart = nil
            tasks[0].scheduledEnd = nil
            tasks[0].isPinned = false
        }
    }

    // MARK: - Recurrence detection

    private enum Recurrence {
        case daily(count: Int)
        case weekly(weekday: Int, count: Int)
        case monthly(day: Int, count: Int)
    }

    private static func detectRecurrence(in text: String) -> (recurrence: Recurrence?, cleaned: String) {
        var working = text
        let ns = working as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Daily: "every day"
        if let match = Cache.everyDayRegex.firstMatch(in: working, range: fullRange) {
            if let r = Range(match.range, in: working) { working.removeSubrange(r) }
            return (.daily(count: 30), working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Weekly: "every thursday"
        if let match = Cache.everyWeekdayRegex.firstMatch(in: working, range: fullRange) {
            let dayName = ns.substring(with: match.range(at: 1)).lowercased()
            if let weekday = weekdayIndex(for: dayName) {
                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return (.weekly(weekday: weekday, count: 12), working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Monthly: "on the 25th of every month" or "every month on the 25th" or "monthly on the 25th"
        for regex in Cache.monthlyRegexes {
            if let match = regex.firstMatch(in: working, range: fullRange) {
                var day: Int = 1
                if match.numberOfRanges >= 2 {
                    let rg = match.range(at: 1)
                    if rg.location != NSNotFound, let d = Int(ns.substring(with: rg)) { day = d }
                }
                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return (.monthly(day: max(1, min(31, day)), count: 12), working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return (nil, text)
    }

    private static func duplicate(task base: TaskItem, for rec: Recurrence, reference now: Date) -> [TaskItem] {
        let cal = Calendar.current

        func withDate(_ day: Date, from base: TaskItem) -> TaskItem {
            var t = base
            if let start = base.scheduledStart {
                let comps = cal.dateComponents([.hour, .minute, .second], from: start)
                var dayComps = cal.dateComponents([.year, .month, .day], from: day)
                dayComps.hour = comps.hour
                dayComps.minute = comps.minute
                dayComps.second = comps.second
                let newStart = cal.date(from: dayComps)
                t.scheduledStart = newStart
                if let newStart {
                    t.scheduledEnd = newStart.addingTimeInterval(TimeInterval(max(5, base.estimatedMinutes) * 60))
                }
            } else {
                // No explicit time: default to 9:00 AM
                var dayComps = cal.dateComponents([.year, .month, .day], from: day)
                dayComps.hour = 9
                dayComps.minute = 0
                let newStart = cal.date(from: dayComps)
                t.scheduledStart = newStart
                if let newStart {
                    t.scheduledEnd = newStart.addingTimeInterval(TimeInterval(max(5, base.estimatedMinutes) * 60))
                }
            }
            t.id = UUID()
            t.isCompleted = false
            return t
        }

        var out: [TaskItem] = []
        switch rec {
        case .daily(let count):
            for i in 0..<count {
                if let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: now)) {
                    out.append(withDate(day, from: base))
                }
            }
        case .weekly(let weekday, let count):
            // Find the next occurrence of the requested weekday (including today if matches and time not past)
            var day = now
            while cal.component(.weekday, from: day) != weekday {
                day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            }
            for i in 0..<count {
                if let d = cal.date(byAdding: .day, value: i * 7, to: cal.startOfDay(for: day)) {
                    out.append(withDate(d, from: base))
                }
            }
        case .monthly(let dayOfMonth, let count):
            let start = cal.startOfDay(for: now)
            let ym = cal.dateComponents([.year, .month], from: start)
            let monthStart = cal.date(from: ym) ?? start
            for i in 0..<count {
                if let m = cal.date(byAdding: .month, value: i, to: monthStart), let range = cal.range(of: .day, in: .month, for: m) {
                    let d = min(dayOfMonth, range.count)
                    var comps = cal.dateComponents([.year, .month], from: m)
                    comps.day = d
                    if let day = cal.date(from: comps) {
                        out.append(withDate(day, from: base))
                    }
                }
            }
        }
        return out
    }

    // MARK: - Pre-processing

    private static func normalize(_ text: String) -> String {
        var s = text

        s = s
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Fix common speech-to-text mistakes for "then"
        s = s.replacingOccurrences(of: #"(?i)\bthank\b"#, with: " then ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bthan\b"#, with: " then ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bthem\b"#, with: " then ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bweday\b"#, with: "wednesday", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bmotnh\b"#, with: "month", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bnoe\b"#, with: "now", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btommorow\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btomorow\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btommorrow\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btommporw\b"#, with: "tomorrow", options: .regularExpression)

        // Convert "7;30" -> "7:30"
        s = s.replacingOccurrences(of: #"(\d)\s*;\s*(\d{2})"#, with: "$1:$2", options: .regularExpression)

        // Convert "7.30" -> "7:30"
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2})\s*\.\s*(\d{2})\b"#, with: "$1:$2", options: .regularExpression)

        // Normalize "a.m." / "p.m." to am/pm
        s = s.replacingOccurrences(of: #"(?i)\ba\.?\s*m\.?\b"#, with: "am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bp\.?\s*m\.?\b"#, with: "pm", options: .regularExpression)

        // Convert "half past six" -> "6:30", etc
        s = normalizeSpokenClockPhrases(s)

        // Convert spelled-out hours in time contexts: "at six", "from three", etc
        s = replaceNumberWordsInTimeContexts(s)

        // Convert spelled-out duration numbers: "two hours", "three minutes"
        s = replaceNumberWordsInDurationContexts(s)

        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return s
    }

    private static func normalizeSpokenClockPhrases(_ input: String) -> String {
        var s = input

        let wordToHour = Cache.numberWordMap

        func replaceAll(_ regex: NSRegularExpression, transform: (NSTextCheckingResult, NSString) -> String) {

            // Compute matches once, apply in reverse so ranges stay valid
            let original = s as NSString
            let matches = regex.matches(in: s, range: NSRange(location: 0, length: original.length)).reversed()

            for m in matches {
                let current = s as NSString
                let replacement = transform(m, current)
                s = current.replacingCharacters(in: m.range, with: replacement)
            }
        }

        // half past X => X:30
        replaceAll(Cache.halfPastRegex) { m, ns in
            let w = ns.substring(with: m.range(at: 1)).lowercased()
            let h = wordToHour[w] ?? 0
            return "\(h):30"
        }

        // quarter past X => X:15
        replaceAll(Cache.quarterPastRegex) { m, ns in
            let w = ns.substring(with: m.range(at: 1)).lowercased()
            let h = wordToHour[w] ?? 0
            return "\(h):15"
        }

        // quarter to X => (X-1):45
        replaceAll(Cache.quarterToRegex) { m, ns in
            let w = ns.substring(with: m.range(at: 1)).lowercased()
            let hh = wordToHour[w] ?? 0
            let h = (hh == 1) ? 12 : max(1, hh - 1)
            return "\(h):45"
        }

        return s
    }

    private static func replaceNumberWordsInTimeContexts(_ input: String) -> String {
        var s = input
        let map = Cache.numberWordMap
        let r = Cache.timeContextRegex

        let ns = s as NSString
        let matches = r.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            guard m.numberOfRanges >= 3 else { continue }
            let pre = ns.substring(with: m.range(at: 1)).lowercased()
            let word = ns.substring(with: m.range(at: 2)).lowercased()
            if let n = map[word] {
                s = (s as NSString).replacingCharacters(in: m.range, with: "\(pre) \(n)")
            }
        }

        return s
    }

    private static func replaceNumberWordsInDurationContexts(_ input: String) -> String {
        var s = input
        let map = Cache.numberWordMap
        let r = Cache.durationWordRegex

        let ns = s as NSString
        let matches = r.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let word = ns.substring(with: m.range(at: 1)).lowercased()
            let unit = ns.substring(with: m.range(at: 2))
            if let n = map[word] {
                s = (s as NSString).replacingCharacters(in: m.range, with: "\(n) \(unit)")
            }
        }

        return s
    }

    // MARK: - Chunking

    private static func splitIntoChunks(_ text: String) -> [String] {
        // For efficiency, replace many separators in one regex pass and split once.
        // We intentionally do NOT treat "next" as a delimiter here, since it appears in time windows.
        let ns = text as NSString
        let replaced = Cache.primaryChunkDelimiterRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "|"
        )

        var chunks: [String] = replaced
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Split on standalone "next" when it is *not* the time-window phrase "next 30 mins/hours".
        chunks = chunks.flatMap { splitOnStandaloneNext($0) }

        // Avoid breaking "between X and Y" while still splitting on plain "and".
        chunks = chunks.flatMap { c in
            let ns2 = c as NSString
            let full = NSRange(location: 0, length: ns2.length)
            if Cache.betweenAndRegex.firstMatch(in: c, range: full) != nil {
                return [c]
            }
            return splitByDelimiterRegex(c, regex: Cache.andDelimiterRegex)
        }

        // Split multiple time markers early so later heuristics don't accidentally break them.
        var finalChunks: [String] = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        finalChunks = finalChunks.flatMap { splitOnMultipleTimeMarkers($0) }
        finalChunks = finalChunks.flatMap { splitOnPhrases($0) }
        finalChunks = finalChunks.flatMap { splitFusedActions($0) }

        return finalChunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitByDelimiterRegex(_ s: String, regex: NSRegularExpression) -> [String] {
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: s, range: range)
        guard !matches.isEmpty else { return [s] }

        var out: [String] = []
        var last = 0
        for m in matches {
            let end = m.range.location
            if end > last {
                let piece = ns.substring(with: NSRange(location: last, length: end - last))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { out.append(piece) }
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            let piece = ns.substring(with: NSRange(location: last, length: ns.length - last))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
        }
        return out.isEmpty ? [s] : out
    }

    /// Splits on specific multi-word phrases to separate tasks like "unpack go to bed at midnight" → ["unpack", "go to bed at midnight"].
    private static func splitOnPhrases(_ chunk: String) -> [String] {
        let s = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }

        // Phrases to split on (kept with the right-hand piece)
        let phrases = [
            "go to bed",
            "go to sleep",
            "head to bed"
        ]
        let lower = s.lowercased()
        for phrase in phrases {
            if let r = lower.range(of: phrase), r.lowerBound > lower.startIndex {
                let left = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(s[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty && !right.isEmpty { return [left, right] }
            }
        }
        return [s]
    }

    /// Splits "shower eat snack study" into separate chunks when user doesn't type separators.
    private static func splitFusedActions(_ chunk: String) -> [String] {
        let s = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }

        let lower = s.lowercased()

        // If user already used separators, don't get cute.
        let obviousSeps = [" and ", " then ", ",", ";", "\n", " - "]
        if obviousSeps.contains(where: { lower.contains($0) }) { return [s] }

        // If there's an explicit time marker ("at 9", "by midnight", etc.), avoid splitting.
        // Time markers usually provide the structure and we don't want to split phrases like "go for a 15 min walk at 5".
        let ns = s as NSString
        if Cache.timeMarkerSplitRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil {
            return [s]
        }

        // Don’t try to split chunks that still look like they contain a time range.
        if lower.contains(" from ") || lower.contains(" between ") || lower.contains(" until ") || lower.contains(" till ") {
            return [s]
        }

        // Find verb starts
        let regex = Cache.fusedVerbRegex
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.count < 2 { return [s] }

        // Collect split points
        let starts = matches.map { $0.range.location }.sorted()
        guard starts.first == 0 || starts.first ?? 0 < ns.length else { return [s] }

        // Build slices
        var pieces: [String] = []
        for i in 0..<starts.count {
            let start = starts[i]
            let end = (i + 1 < starts.count) ? starts[i + 1] : ns.length
            if end > start {
                let piece = ns.substring(with: NSRange(location: start, length: end - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if piece.count >= 3 { pieces.append(piece) }
            }
        }

        // If splitting created nonsense, fall back
        if pieces.count < 2 { return [s] }
        return pieces
    }

    private static func splitOnStandaloneNext(_ chunk: String) -> [String] {
        let s = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }

        // If this looks like a time-window phrase, keep intact.
        if s.range(of: #"(?i)\b(?:in\s+the\s+)?next\s+\d+\s*(?:m|mins?|minutes?|h|hrs?|hours?)\b"#, options: .regularExpression) != nil {
            return [s]
        }

        // If "next" is a day qualifier, keep intact.
        if s.range(of: #"(?i)\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|year)\b"#, options: .regularExpression) != nil {
            return [s]
        }

        return s.components(separatedBy: " next ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Splits chunks with multiple explicit time markers like "at 9 breakfast at 10 study".
    private static func splitOnMultipleTimeMarkers(_ chunk: String) -> [String] {
        let s = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }

        // Avoid splitting explicit ranges.
        let lower = s.lowercased()
        if lower.contains(" from ") || lower.contains(" between ") { return [s] }

        let ns = s as NSString
        let matches = Cache.timeMarkerSplitRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.count < 2 { return [s] }

        // Two common styles:
        // 1) Prefix: "at 9 breakfast at 10 study"  -> split at each marker start.
        // 2) Postfix: "breakfast at 9 study at 10" -> split after each marker (and optional duration).
        let prefixStyle = lower.hasPrefix("at ") || lower.hasPrefix("by ") || lower.hasPrefix("around ")
        if prefixStyle {
            var pieces: [String] = []
            if matches[0].range.location > 0 {
                let head = ns.substring(with: NSRange(location: 0, length: matches[0].range.location))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty { pieces.append(head) }
            }
            for i in 0..<matches.count {
                let start = matches[i].range.location
                let end = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
                if end > start {
                    let piece = ns.substring(with: NSRange(location: start, length: end - start))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !piece.isEmpty { pieces.append(piece) }
                }
            }
            return pieces.isEmpty ? [s] : pieces
        }

        func leadingDurationLength(in text: String) -> Int? {
            let ns2 = text as NSString
            let range = NSRange(location: 0, length: ns2.length)
            if let match = Cache.leadingDurationRegex.firstMatch(in: text, range: range) {
                return match.range.length
            }
            return nil
        }

        var pieces: [String] = []
        var start = 0

        for i in 0..<matches.count {
            let match = matches[i]
            let markerEnd = match.range.location + match.range.length
            let nextStart = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length

            var pieceEnd = markerEnd
            if markerEnd < nextStart {
                let remainder = ns.substring(with: NSRange(location: markerEnd, length: nextStart - markerEnd))
                if let durLen = leadingDurationLength(in: remainder) {
                    pieceEnd = min(ns.length, markerEnd + durLen)
                }
            }

            if pieceEnd > start {
                let piece = ns.substring(with: NSRange(location: start, length: pieceEnd - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { pieces.append(piece) }
            }
            start = pieceEnd
        }

        if start < ns.length {
            let tail = ns.substring(with: NSRange(location: start, length: ns.length - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { pieces.append(tail) }
        }

        return pieces.isEmpty ? [s] : pieces
    }

    // MARK: - Chunk → Task

    private static func parseChunk(_ chunk: String, now: Date, minConfidence: TimeConfidence) -> TaskItem? {
        var text = chunk

        let timeResult = extractTime(from: text, now: now)
        let dueDate = timeResult.date
        let timeConfidence = timeResult.confidence
        text = timeResult.cleaned

        let durationResult = extractDuration(from: text)
        var minutes = durationResult.minutes
        text = durationResult.cleaned

        if let override = timeResult.durationOverrideMinutes {
            minutes = override
        }

        let priorityResult = extractPriority(from: text)
        let priority = priorityResult.priority
        text = priorityResult.cleaned

        let title = cleanedTitle(from: text)
        guard !title.isEmpty else { return nil }

        // Map parsed time info to TaskItem's scheduling fields.
        // If we have an explicit clock time or a time range, set scheduledStart and scheduledEnd.
        let scheduledStart: Date?
        let scheduledEnd: Date?
        if let start = (timeConfidence >= minConfidence) ? dueDate : nil {
            scheduledStart = start
            if minutes > 0 {
                scheduledEnd = Calendar.current.date(byAdding: .minute, value: minutes, to: start)
            } else {
                scheduledEnd = nil
            }
        } else {
            scheduledStart = nil
            scheduledEnd = nil
        }

        return TaskItem(
            title: title,
            estimatedMinutes: minutes,
            priority: priority,
            isPinned: scheduledStart != nil,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd
        )
    }

    // MARK: - Time parsing

    private struct TimeParseResult {
        let date: Date?
        let cleaned: String
        let confidence: TimeConfidence
        let durationOverrideMinutes: Int?
    }

    private enum TimeConfidence: Int, Comparable {
        case low
        case medium
        case high

        static func < (lhs: TimeConfidence, rhs: TimeConfidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private static func extractTime(from text: String, now: Date) -> TimeParseResult {
        var working = text
        let calendar = Calendar.current

        let dayResult = extractBaseDay(from: working, now: now)
        let baseDay = dayResult.baseDay
        let hasExplicitDay = dayResult.hasExplicitDay
        working = dayResult.cleaned

        // "in the next 30 minutes" → start now (rounded) with duration override
        if let next = extractNextWindow(from: working) {
            working = next.cleaned

            let start = roundUp(now, toMinutes: 5, calendar: calendar)
            return TimeParseResult(date: start,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .high,
                                   durationOverrideMinutes: max(5, next.minutes))
        }

        if let rel = extractRelativeTime(from: working, now: now) {
            working = rel.cleaned
            return TimeParseResult(date: rel.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .high,
                                   durationOverrideMinutes: nil)
        }

        if let range = extractTimeRange(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = range.cleaned
            return TimeParseResult(date: range.start,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: range.confidence,
                                   durationOverrideMinutes: max(5, range.minutes))
        }

        if let until = extractUntilTime(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = until.cleaned

            let start = roundUp(now, toMinutes: 5, calendar: calendar)
            return TimeParseResult(date: start,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: until.confidence,
                                   durationOverrideMinutes: max(5, until.minutes))
        }

        if let single = extractSingleClockTime(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = single.cleaned
            return TimeParseResult(date: single.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: single.confidence,
                                   durationOverrideMinutes: nil)
        }

        if let kw = extractKeywordTime(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = kw.cleaned
            return TimeParseResult(date: kw.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .high,
                                   durationOverrideMinutes: nil)
        }

        if let pod = inferPartOfDayIfPresent(from: working, baseDay: baseDay ?? now) {
            working = pod.cleaned
            return TimeParseResult(date: pod.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .low,
                                   durationOverrideMinutes: nil)
        }

        return TimeParseResult(date: nil,
                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                               confidence: .low,
                               durationOverrideMinutes: nil)
    }

    // MARK: - Base day extraction

    private struct BaseDayResult {
        let baseDay: Date?
        let cleaned: String
        let hasExplicitDay: Bool
    }

    private static func extractBaseDay(from text: String, now: Date) -> BaseDayResult {
        var working = text
        let calendar = Calendar.current
        var baseDay: Date? = nil
        var explicitDay = false

        func removeMatch(_ range: NSRange) {
            if let r = Range(range, in: working) { working.removeSubrange(r) }
        }

        let monthRegex = Cache.monthDayRegex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = monthRegex.firstMatch(in: working, range: range) {
                let mName = ns.substring(with: match.range(at: 1))
                let dStr = ns.substring(with: match.range(at: 2))
                let yRange = match.range(at: 3)
                let yStr = (yRange.location != NSNotFound) ? ns.substring(with: yRange) : nil

                if let month = monthIndex(for: mName),
                   let day = Int(dStr) {
                    let currentYear = calendar.component(.year, from: now)
                    var year = yStr.flatMap { Int($0) } ?? currentYear

                    var comps = DateComponents()
                    comps.year = year
                    comps.month = month
                    comps.day = day
                    comps.hour = 0
                    comps.minute = 0

                    if let date0 = calendar.date(from: comps) {
                        if yStr == nil && calendar.startOfDay(for: date0) < calendar.startOfDay(for: now) {
                            year += 1
                            comps.year = year
                        }
                        baseDay = calendar.date(from: comps)
                        explicitDay = true
                        removeMatch(match.range)
                    }
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.numericDateRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let mStr = ns.substring(with: match.range(at: 1))
                let dStr = ns.substring(with: match.range(at: 2))
                let yRange = match.range(at: 3)
                let yStr = (yRange.location != NSNotFound) ? ns.substring(with: yRange) : nil

                if let m = Int(mStr), let d = Int(dStr) {
                    let currentYear = calendar.component(.year, from: now)
                    let year: Int
                    if let yStr = yStr, let y = Int(yStr) {
                        year = (y < 100) ? (2000 + y) : y
                    } else {
                        year = currentYear
                    }

                    var comps = DateComponents()
                    comps.year = year
                    comps.month = m
                    comps.day = d
                    comps.hour = 0
                    comps.minute = 0

                    if let date0 = calendar.date(from: comps) {
                        if yStr == nil && calendar.startOfDay(for: date0) < calendar.startOfDay(for: now) {
                            comps.year = year + 1
                        }
                        baseDay = calendar.date(from: comps)
                        explicitDay = true
                        removeMatch(match.range)
                    }
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.weekdayOrdinalRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let dayName = ns.substring(with: match.range(at: 1))
                let dayNum = Int(ns.substring(with: match.range(at: 2))) ?? -1

                if let weekday = weekdayIndex(for: dayName),
                   (1...31).contains(dayNum),
                   let resolved = dateFor(weekday: weekday, dayOfMonth: dayNum, reference: now) {
                    baseDay = resolved
                    explicitDay = true
                    removeMatch(match.range)
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.dayOfWeekRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let qualRange = match.range(at: 1)
                let qualifier = (qualRange.location != NSNotFound) ? ns.substring(with: qualRange) : nil
                let dayName = ns.substring(with: match.range(at: 2))

                if let weekday = weekdayIndex(for: dayName) {
                    baseDay = dateFor(qualifier: qualifier, weekday: weekday, reference: now)
                    explicitDay = true
                    removeMatch(match.range)
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.tomorrowVariantsRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                explicitDay = true
                removeMatch(match.range)
            }
        }

        let lower = working.lowercased()
        if baseDay == nil, lower.contains("today") {
            working = working.replacingOccurrences(of: "today", with: "", options: .caseInsensitive)
            baseDay = calendar.startOfDay(for: now)
            explicitDay = true
        }

        if baseDay == nil {
            let regex = Cache.relativeDayRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let nStr = ns.substring(with: match.range(at: 1))
                let unit = ns.substring(with: match.range(at: 2)).lowercased()
                if let n = Int(nStr) {
                    let deltaDays = unit.hasPrefix("week") ? (n * 7) : n
                    baseDay = calendar.date(byAdding: .day, value: deltaDays, to: calendar.startOfDay(for: now))
                    explicitDay = true
                    removeMatch(match.range)
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.relativeFromNowRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let nStr = ns.substring(with: match.range(at: 1))
                let unit = ns.substring(with: match.range(at: 2)).lowercased()
                if let n = Int(nStr), n >= 0 {
                    let deltaDays = unit.hasPrefix("week") ? (n * 7) : n
                    baseDay = calendar.date(byAdding: .day, value: deltaDays, to: calendar.startOfDay(for: now))
                    explicitDay = true
                    removeMatch(match.range)
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.nextMonthRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let start = calendar.startOfDay(for: now)
                let ym = calendar.dateComponents([.year, .month], from: start)
                let thisMonthStart = calendar.date(from: ym) ?? start
                if let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) {
                    baseDay = nextMonthStart
                    explicitDay = true
                    removeMatch(match.range)
                }
            }
        }

        return BaseDayResult(baseDay: baseDay,
                             cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                             hasExplicitDay: explicitDay)
    }

    private static func monthIndex(for name: String) -> Int? {
        switch name.lowercased() {
        case "january", "jan": return 1
        case "february", "feb": return 2
        case "march", "mar": return 3
        case "april", "apr": return 4
        case "may": return 5
        case "june", "jun": return 6
        case "july", "jul": return 7
        case "august", "aug": return 8
        case "september", "sep", "sept": return 9
        case "october", "oct": return 10
        case "november", "nov": return 11
        case "december", "dec": return 12
        default: return nil
        }
    }

    private static func weekdayIndex(for name: String) -> Int? {
        switch name.lowercased() {
        case "sunday": return 1
        case "monday": return 2
        case "tuesday": return 3
        case "wednesday": return 4
        case "thursday": return 5
        case "friday": return 6
        case "saturday": return 7
        default: return nil
        }
    }

    private static func dateFor(qualifier: String?, weekday: Int, reference: Date) -> Date {
        let cal = Calendar.current
        let refWeekday = cal.component(.weekday, from: reference)
        var delta = (weekday - refWeekday + 7) % 7
        let q = qualifier?.lowercased() ?? ""

        if q.contains("next") {
            delta = (delta == 0) ? 7 : (delta + 7)
        }
        let start = cal.startOfDay(for: reference)
        return cal.date(byAdding: .day, value: delta, to: start) ?? start
    }

    private static func dateFor(weekday: Int, dayOfMonth: Int, reference: Date) -> Date? {
        let cal = Calendar.current
        let refStart = cal.startOfDay(for: reference)
        let startComps = cal.dateComponents([.year, .month], from: refStart)
        guard let monthStart = cal.date(from: startComps) else { return nil }

        for i in 0..<24 {
            guard let candidateMonth = cal.date(byAdding: .month, value: i, to: monthStart),
                  let dayRange = cal.range(of: .day, in: .month, for: candidateMonth),
                  dayOfMonth <= dayRange.count else { continue }

            var comps = cal.dateComponents([.year, .month], from: candidateMonth)
            comps.day = dayOfMonth
            comps.hour = 0
            comps.minute = 0
            comps.second = 0

            guard let date = cal.date(from: comps) else { continue }
            if date < refStart { continue }
            if cal.component(.weekday, from: date) == weekday {
                return date
            }
        }

        return nil
    }

    // MARK: - Relative time

    private struct NextWindowResult {
        let minutes: Int
        let cleaned: String
    }

    /// Parses phrases like "in the next 30 mins" / "over the next 2 hours".
    /// This is treated as "start now (rounded)" with a duration override.
    private static func extractNextWindow(from text: String) -> NextWindowResult? {
        var working = text

        let regex = Cache.nextWindowRegex
        let ns = working as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let match = regex.firstMatch(in: working, range: range) {
            let nStr = ns.substring(with: match.range(at: 1))
            let unit = ns.substring(with: match.range(at: 2)).lowercased()
            if let n = Int(nStr), n > 0 {
                let minutes = (unit.hasPrefix("hour") || unit.hasPrefix("hr")) ? (n * 60) : n
                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return NextWindowResult(minutes: max(5, minutes), cleaned: working)
            }
        }

        // "next 30 mins" (without "in the")
        let shortRegex = Cache.nextWindowShortRegex
        if let match = shortRegex.firstMatch(in: working, range: range) {
            let nStr = ns.substring(with: match.range(at: 1))
            let unit = ns.substring(with: match.range(at: 2)).lowercased()
            if let n = Int(nStr), n > 0 {
                let minutes = (unit.hasPrefix("hour") || unit.hasPrefix("hr")) ? (n * 60) : n
                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return NextWindowResult(minutes: max(5, minutes), cleaned: working)
            }
        }

        if working.lowercased().contains("in the next half hour") {
            working = working.replacingOccurrences(of: "in the next half hour", with: "", options: .caseInsensitive)
            return NextWindowResult(minutes: 30, cleaned: working)
        }

        return nil
    }

    private struct RelativeTimeResult {
        let date: Date
        let cleaned: String
    }

    private static func extractRelativeTime(from text: String, now: Date) -> RelativeTimeResult? {
        var working = text
        let cal = Calendar.current

        let regex = Cache.relativeTimeRegex
        let ns = working as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let match = regex.firstMatch(in: working, range: range) {
            let nStr = ns.substring(with: match.range(at: 1))
            let unit = ns.substring(with: match.range(at: 2)).lowercased()
            if let n = Int(nStr) {
                let date: Date = (unit.hasPrefix("hour") || unit.hasPrefix("hr"))
                    ? (cal.date(byAdding: .minute, value: n * 60, to: now) ?? now)
                    : (cal.date(byAdding: .minute, value: n, to: now) ?? now)

                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return RelativeTimeResult(date: date, cleaned: working)
            }
        }

        if working.lowercased().contains("in half an hour") || working.lowercased().contains("in a half hour") {
            working = working.replacingOccurrences(of: "in half an hour", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "in a half hour", with: "", options: .caseInsensitive)
            let date = cal.date(byAdding: .minute, value: 30, to: now) ?? now
            return RelativeTimeResult(date: date, cleaned: working)
        }

        return nil
    }

    // MARK: - Time range parsing (fixed to avoid "1-2 hours" false matches)

    private struct TimeRangeResult {
        let start: Date
        let end: Date
        let minutes: Int
        let cleaned: String
        let confidence: TimeConfidence
    }

    private static func extractTimeRange(from text: String, baseDay: Date, hasExplicitDay: Bool, now: Date) -> TimeRangeResult? {
        var working = text
        let cal = Calendar.current
        let context = working.lowercased()

        // Require "from/between" OR a real clock token like "7:30" or "7pm"
        let regex = Cache.timeRangeRegex
        let ns = working as NSString
        let searchRange = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: working, range: searchRange) else { return nil }

        let leadRange = match.range(at: 1)
        let hasFromBetween = (leadRange.location != NSNotFound)

        let raw1 = ns.substring(with: match.range(at: 2))
        let raw2 = ns.substring(with: match.range(at: 5))
        let h1 = Int(raw1) ?? -1
        let h2 = Int(raw2) ?? -1
        if !(1...23).contains(h1) || !(1...23).contains(h2) { return nil }

        let m1 = Int((match.range(at: 3).location != NSNotFound) ? ns.substring(with: match.range(at: 3)) : "0") ?? 0
        let m2 = Int((match.range(at: 6).location != NSNotFound) ? ns.substring(with: match.range(at: 6)) : "0") ?? 0
        let ap1 = (match.range(at: 4).location != NSNotFound) ? ns.substring(with: match.range(at: 4)).lowercased() : nil
        let ap2 = (match.range(at: 7).location != NSNotFound) ? ns.substring(with: match.range(at: 7)).lowercased() : nil

        // If there's no "from/between" AND neither side has ":" or am/pm, it’s probably "1-2 hours". Bail.
        let hasColon = (match.range(at: 3).location != NSNotFound) || (match.range(at: 6).location != NSNotFound)
        let hasMeridiem = (ap1 != nil || ap2 != nil)
        if !hasFromBetween && !hasColon && !hasMeridiem { return nil }

        let startParts = inferHourMinute(hour: h1, minute: m1, ampm: ap1, context: context, now: now)
        let endParts   = inferHourMinute(hour: h2, minute: m2, ampm: ap2 ?? ap1, context: context, now: now)

        guard let start0 = buildDate(on: baseDay, hour24: startParts.hour24, minute: startParts.minute),
              var end0 = buildDate(on: baseDay, hour24: endParts.hour24, minute: endParts.minute) else {
            return nil
        }

        if end0 <= start0 {
            end0 = cal.date(byAdding: .day, value: 1, to: end0) ?? end0
        }

        var start = start0
        var end = end0

        if !hasExplicitDay, now > start && now < end {
            start = roundUp(now, toMinutes: 5, calendar: cal)
        }

        if !hasExplicitDay, end < now {
            start = cal.date(byAdding: .day, value: 1, to: start) ?? start
            end = cal.date(byAdding: .day, value: 1, to: end) ?? end
        }

        let mins = Int(end.timeIntervalSince(start) / 60.0)
        let confidence = min(startParts.confidence, endParts.confidence)

        if let r = Range(match.range, in: working) { working.removeSubrange(r) }
        return TimeRangeResult(start: start, end: end, minutes: max(5, mins), cleaned: working, confidence: confidence)
    }

    // MARK: - "until X"

    private struct UntilResult {
        let minutes: Int
        let cleaned: String
        let confidence: TimeConfidence
    }

    private static func extractUntilTime(from text: String, baseDay: Date, hasExplicitDay: Bool, now: Date) -> UntilResult? {
        var working = text
        let cal = Calendar.current

        let regex = Cache.untilRegex
        let ns = working as NSString
        let searchRange = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: working, range: searchRange) else { return nil }

        let hh = Int(ns.substring(with: match.range(at: 1))) ?? -1
        if !(1...23).contains(hh) { return nil }
        let mm = Int((match.range(at: 2).location != NSNotFound) ? ns.substring(with: match.range(at: 2)) : "0") ?? 0
        let ap = (match.range(at: 3).location != NSNotFound) ? ns.substring(with: match.range(at: 3)).lowercased() : nil

        let endParts = inferHourMinute(hour: hh, minute: mm, ampm: ap, context: working.lowercased(), now: now)
        guard var end = buildDate(on: baseDay, hour24: endParts.hour24, minute: endParts.minute) else { return nil }

        if !hasExplicitDay, end < now {
            end = cal.date(byAdding: .day, value: 1, to: end) ?? end
        }

        let start = roundUp(now, toMinutes: 5, calendar: cal)
        let mins = Int(end.timeIntervalSince(start) / 60.0)
        if mins <= 0 { return nil }

        if let r = Range(match.range, in: working) { working.removeSubrange(r) }
        return UntilResult(minutes: max(5, mins), cleaned: working, confidence: endParts.confidence)
    }

    // MARK: - Single time parsing

    private struct SingleTimeResult {
        let date: Date
        let cleaned: String
        let confidence: TimeConfidence
    }

    private static func extractSingleClockTime(from text: String, baseDay: Date, hasExplicitDay: Bool, now: Date) -> SingleTimeResult? {
        var working = text
        let cal = Calendar.current
        let context = working.lowercased()

        func removeRange(_ range: NSRange) {
            if let r = Range(range, in: working) { working.removeSubrange(r) }
        }

        // 24h "18:30"
        let regex24 = Cache.time24Regex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex24.firstMatch(in: working, range: range) {
                let h = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let m = Int(ns.substring(with: match.range(at: 2))) ?? 0
                if var date = buildDate(on: baseDay, hour24: h, minute: m) {
                    if !hasExplicitDay, date < now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
                    removeRange(match.range)
                    return SingleTimeResult(date: date, cleaned: working, confidence: .high)
                }
            }
        }

        // 12h "7pm" "6:30am"
        let regex12 = Cache.time12Regex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex12.firstMatch(in: working, range: range) {
                let h = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let m = Int((match.range(at: 2).location != NSNotFound) ? ns.substring(with: match.range(at: 2)) : "0") ?? 0
                let ap = ns.substring(with: match.range(at: 3)).lowercased()

                let h24: Int = (ap == "pm")
                    ? ((h == 12) ? 12 : h + 12)
                    : ((h == 12) ? 0 : h)

                if var date = buildDate(on: baseDay, hour24: h24, minute: m) {
                    if !hasExplicitDay, date < now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
                    removeRange(match.range)
                    return SingleTimeResult(date: date, cleaned: working, confidence: .high)
                }
            }
        }

        // "7:30" infer AM/PM
        let regexColonNoMeridiem = Cache.timeColonNoMeridiemRegex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regexColonNoMeridiem.firstMatch(in: working, range: range) {
                let h = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let m = Int(ns.substring(with: match.range(at: 2))) ?? 0

                let parts = inferHourMinute(hour: h, minute: m, ampm: nil, context: context, now: now)
                if var date = buildDate(on: baseDay, hour24: parts.hour24, minute: parts.minute) {
                    if !hasExplicitDay, date < now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
                    removeRange(match.range)
                    return SingleTimeResult(date: date, cleaned: working, confidence: parts.confidence)
                }
            }
        }

        // "at 730" / "by 1730"
        let regexCompact = Cache.timeCompactRegex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regexCompact.firstMatch(in: working, range: range) {
                let token = ns.substring(with: match.range(at: 1))
                if let (h, m) = parseCompactTime(token) {
                    let parts: InferredTimeParts = (h > 12)
                        ? InferredTimeParts(hour24: h, minute: m, confidence: .high)
                        : inferHourMinute(hour: h, minute: m, ampm: nil, context: context, now: now)

                    if var date = buildDate(on: baseDay, hour24: parts.hour24, minute: parts.minute) {
                        if !hasExplicitDay, date < now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
                        removeRange(match.range)
                        return SingleTimeResult(date: date, cleaned: working, confidence: parts.confidence)
                    }
                }
            }
        }

        // "at 6" infer AM/PM
        let regexBareHour = Cache.timeBareHourRegex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regexBareHour.firstMatch(in: working, range: range) {
                let h = Int(ns.substring(with: match.range(at: 1))) ?? 0
                guard (1...12).contains(h) else { return nil }

                let parts = inferHourMinute(hour: h, minute: 0, ampm: nil, context: context, now: now)
                if var date = buildDate(on: baseDay, hour24: parts.hour24, minute: parts.minute) {
                    if !hasExplicitDay, date < now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
                    removeRange(match.range)
                    return SingleTimeResult(date: date, cleaned: working, confidence: parts.confidence)
                }
            }
        }

        return nil
    }

    private struct KeywordTimeResult {
        let date: Date
        let cleaned: String
    }

    private static func extractKeywordTime(from text: String, baseDay: Date, hasExplicitDay: Bool, now: Date) -> KeywordTimeResult? {
        var working = text
        let cal = Calendar.current

        func remove(_ range: NSRange) {
            if let r = Range(range, in: working) { working.removeSubrange(r) }
        }

        // Patterns for "midnight" and "noon" (optionally preceded by at/by/around)
        let patterns: [(NSRegularExpression, (Int, Int))] = [
            (Cache.midnightRegex, (0, 0)),
            (Cache.noonRegex, (12, 0)),
            (Cache.eodRegex, (17, 0))
        ]

        for (regex, hm) in patterns {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let (h, m) = hm
                var date = buildDate(on: baseDay, hour24: h, minute: m) ?? baseDay
                if !hasExplicitDay, date < now {
                    date = cal.date(byAdding: .day, value: 1, to: date) ?? date
                }
                remove(match.range)
                return KeywordTimeResult(date: date, cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    // MARK: - Part-of-day inference

    private struct PartOfDayResult {
        let date: Date
        let cleaned: String
    }

    private static func inferPartOfDayIfPresent(from text: String, baseDay: Date) -> PartOfDayResult? {
        var working = text
        let lower = working.lowercased()

        func setTime(_ h: Int, _ m: Int) -> Date {
            return buildDate(on: baseDay, hour24: h, minute: m) ?? baseDay
        }

        if lower.contains("tonight") {
            working = working.replacingOccurrences(of: "tonight", with: "", options: .caseInsensitive)
            return PartOfDayResult(date: setTime(20, 0), cleaned: working)
        }
        if lower.contains("before bed") || lower.contains("before sleep") {
            working = working.replacingOccurrences(of: "before bed", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "before sleep", with: "", options: .caseInsensitive)
            return PartOfDayResult(date: setTime(21, 0), cleaned: working)
        }
        if lower.contains("after class") || lower.contains("after lecture") {
            working = working.replacingOccurrences(of: "after class", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "after lecture", with: "", options: .caseInsensitive)
            return PartOfDayResult(date: setTime(15, 0), cleaned: working)
        }
        if lower.contains("this evening") || lower.contains("evening") {
            working = working.replacingOccurrences(of: "this evening", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "evening", with: "", options: .caseInsensitive)
            return PartOfDayResult(date: setTime(19, 0), cleaned: working)
        }
        if lower.contains("this afternoon") || lower.contains("afternoon") {
            working = working.replacingOccurrences(of: "this afternoon", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "afternoon", with: "", options: .caseInsensitive)
            return PartOfDayResult(date: setTime(14, 0), cleaned: working)
        }
        if lower.contains("this morning") || lower.contains("morning") {
            working = working.replacingOccurrences(of: "this morning", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "morning", with: "", options: .caseInsensitive)
            return PartOfDayResult(date: setTime(9, 0), cleaned: working)
        }

        if lower.contains("breakfast") {
            return PartOfDayResult(date: setTime(8, 0), cleaned: working)
        }
        if lower.contains("lunch") {
            return PartOfDayResult(date: setTime(12, 30), cleaned: working)
        }
        if lower.contains("dinner") || lower.contains("supper") {
            return PartOfDayResult(date: setTime(18, 30), cleaned: working)
        }

        return nil
    }

    // MARK: - AM/PM inference brain

    private struct InferredTimeParts {
        let hour24: Int
        let minute: Int
        let confidence: TimeConfidence
    }

    private static func inferHourMinute(hour: Int, minute: Int, ampm: String?, context: String, now: Date) -> InferredTimeParts {
        let cal = Calendar.current
        let ctx = context.lowercased()
        let h = hour
        let m = minute

        if h > 12 && h <= 23 { return InferredTimeParts(hour24: h, minute: m, confidence: .high) }

        if let ap = ampm?.lowercased() {
            let h24 = (ap == "pm")
                ? ((h == 12) ? 12 : h + 12)
                : ((h == 12) ? 0 : h)
            return InferredTimeParts(hour24: h24, minute: m, confidence: .high)
        }

        if h == 12 {
            if ctx.contains("midnight") || ctx.contains("bed") || ctx.contains("sleep") || ctx.contains("tonight") {
                return InferredTimeParts(hour24: 0, minute: m, confidence: .high)
            }
            if ctx.contains("lunch") || ctx.contains("noon") {
                return InferredTimeParts(hour24: 12, minute: m, confidence: .high)
            }
            let nowHour = cal.component(.hour, from: now)
            return (nowHour < 11) ? InferredTimeParts(hour24: 12, minute: m, confidence: .medium)
                                  : InferredTimeParts(hour24: 0, minute: m, confidence: .medium)
        }

        let morningWords = ["breakfast", "morning", "early", "sunrise"]
        let afternoonWords = ["afternoon", "lunch"]
        let eveningWords = ["dinner", "evening", "tonight", "supper", "after work"]
        let nightWords = ["night", "club", "clubs", "party", "afterparty"]
        let sleepWords = ["bed", "sleep", "asleep", "nap"]

        let wantsAM = morningWords.contains(where: ctx.contains)
        let wantsPM = eveningWords.contains(where: ctx.contains) || nightWords.contains(where: ctx.contains)
        let wantsSleepTime = sleepWords.contains(where: ctx.contains)

        if wantsSleepTime, h <= 5 { return InferredTimeParts(hour24: h, minute: m, confidence: .high) }
        if wantsAM { return InferredTimeParts(hour24: h, minute: m, confidence: .high) }
        if afternoonWords.contains(where: ctx.contains) { return InferredTimeParts(hour24: h + 12, minute: m, confidence: .high) }
        if wantsPM { return InferredTimeParts(hour24: h + 12, minute: m, confidence: .high) }

        let amH24 = h
        let pmH24 = h + 12

        func score(_ hour24: Int) -> Int {
            let nowH = cal.component(.hour, from: now)
            let nowM = cal.component(.minute, from: now)
            var delta = (hour24 * 60 + m) - (nowH * 60 + nowM)
            if delta < 0 { delta += 24 * 60 }

            var penalty = 0
            if (1...5).contains(hour24) { penalty += 600 }
            if hour24 >= 22 { penalty += 120 }
            if (9...20).contains(hour24) { penalty -= 60 }

            return delta + penalty
        }

        return (score(pmH24) <= score(amH24))
            ? InferredTimeParts(hour24: pmH24, minute: m, confidence: .medium)
            : InferredTimeParts(hour24: amH24, minute: m, confidence: .medium)
    }

    private static func buildDate(on baseDay: Date, hour24: Int, minute: Int) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: baseDay)
        comps.hour = hour24
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps)
    }

    private static func roundUp(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        guard let minute = comps.minute, let hour = comps.hour else { return date }

        let total = hour * 60 + minute
        let rounded = ((total + step - 1) / step) * step
        let newHour = rounded / 60
        let newMin = rounded % 60

        var newComps = comps
        newComps.hour = newHour
        newComps.minute = newMin
        newComps.second = 0

        return calendar.date(from: newComps) ?? date
    }

    private static func parseCompactTime(_ token: String) -> (Int, Int)? {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = Int(t) else { return nil }

        if t.count == 3 {
            let h = n / 100
            let m = n % 100
            if (0...23).contains(h), (0...59).contains(m) { return (h, m) }
        } else if t.count == 4 {
            let h = n / 100
            let m = n % 100
            if (0...23).contains(h), (0...59).contains(m) { return (h, m) }
        }
        return nil
    }

    // MARK: - Duration parsing

    private struct DurationParseResult {
        let minutes: Int
        let cleaned: String
    }

    private static func extractDuration(from text: String) -> DurationParseResult {
        var working = text

        // "for 10 mins" / "for 1.5 hours" (removes the whole phrase, including the glue word)
        let forRegex = Cache.durationForRegex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = forRegex.firstMatch(in: working, range: range) {
                let numStr = ns.substring(with: match.range(at: 1))
                let unit = ns.substring(with: match.range(at: 2)).lowercased()
                if let val = Double(numStr), val > 0 {
                    let mins = (unit.hasPrefix("h") || unit.hasPrefix("hr") || unit.hasPrefix("hour"))
                        ? Int((val * 60.0).rounded())
                        : Int(val.rounded())
                    if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                    return DurationParseResult(minutes: max(5, mins),
                                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        let hourHalfRegex = Cache.durationHourHalfRegex
        do {
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = hourHalfRegex.firstMatch(in: working, range: range) {
                let numStr = ns.substring(with: match.range(at: 1))
                if let val = Double(numStr), val > 0 {
                    let mins = Int((val * 60.0).rounded())
                    if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                    return DurationParseResult(minutes: max(5, mins),
                                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        if working.lowercased().contains("hour and a half") {
            working = working.replacingOccurrences(of: "hour and a half", with: "", options: .caseInsensitive)
            return DurationParseResult(minutes: 90,
                                       cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let comboRegex = Cache.durationComboRegex
        do {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = comboRegex.firstMatch(in: working, range: range) {
                func substring(_ idx: Int) -> String? {
                    let r = match.range(at: idx)
                    guard let rr = Range(r, in: working) else { return nil }
                    return String(working[rr])
                }
                if let hStr = substring(1),
                   let mStr = substring(3),
                   let h = Int(hStr),
                   let m = Int(mStr) {

                    let total = max(5, h * 60 + m)
                    if let fullRange = Range(match.range, in: working) { working.removeSubrange(fullRange) }
                    return DurationParseResult(minutes: total,
                                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        let minRegex = Cache.durationMinutesRegex
        do {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = minRegex.firstMatch(in: working, range: range) {
                if let r = Range(match.range(at: 1), in: working),
                   let minutes = Int(String(working[r])) {
                    if let fullRange = Range(match.range, in: working) { working.removeSubrange(fullRange) }
                    return DurationParseResult(minutes: max(5, minutes),
                                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        let hourRegex = Cache.durationHoursRegex
        do {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = hourRegex.firstMatch(in: working, range: range) {
                if let r = Range(match.range(at: 1), in: working),
                   let hours = Int(String(working[r])) {
                    if let fullRange = Range(match.range, in: working) { working.removeSubrange(fullRange) }
                    return DurationParseResult(minutes: max(5, hours * 60),
                                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        let fuzzy: [(String, Int)] = [
            ("half an hour", 30),
            ("half hour", 30),
            ("an hour", 60),
            ("one hour", 60),
            ("a hour", 60),
            ("a couple of hours", 120),
            ("couple of hours", 120),
            ("a few hours", 120),
            ("few hours", 120)
        ]

        let lower = working.lowercased()
        for (phrase, minutes) in fuzzy {
            if let range = lower.range(of: phrase) {
                let startOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let endOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
                let startIndex = working.index(working.startIndex, offsetBy: startOffset)
                let endIndex = working.index(working.startIndex, offsetBy: endOffset)
                working.removeSubrange(startIndex..<endIndex)
                return DurationParseResult(minutes: minutes,
                                           cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return DurationParseResult(minutes: 30,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Priority parsing

    private struct PriorityParseResult {
        let priority: TaskPriority
        let cleaned: String
    }

    private static func extractPriority(from text: String) -> PriorityParseResult {
        var working = text
        let lower = working.lowercased()

        if lower.contains("urgent") || lower.contains("asap") || lower.contains("high") || lower.contains("important") || lower.contains("must") {
            let remove = ["urgent", "asap", "high", "priority", "prio", "really", "important", "must"]
            for w in remove {
                working = working.replacingOccurrences(of: w, with: "", options: .caseInsensitive)
            }
            return PriorityParseResult(priority: TaskPriority.high,
                                       cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if lower.contains("low") || lower.contains("optional") || lower.contains("if time") {
            working = working.replacingOccurrences(of: "low", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "optional", with: "", options: .caseInsensitive)
            working = working.replacingOccurrences(of: "if time", with: "", options: .caseInsensitive)
            return PriorityParseResult(priority: TaskPriority.low,
                                       cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        working = working.replacingOccurrences(of: "priority", with: "", options: .caseInsensitive)
        return PriorityParseResult(priority: TaskPriority.medium,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Title cleanup

    private static func cleanedTitle(from text: String) -> String {
        var t = text

        let fillers = [
            "i have to", "i need to", "i gotta", "gotta",
            "need to", "have to", "i have", "i need", "i wanna", "i want to",
            "then", "and then", "after that", "next", "thank", "than", "them"
        ]
        for filler in fillers {
            t = t.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
        }

        // Remove common lead-ins (polite or planning phrases)
        let leadingPatterns = [
            #"(?i)^\s*(please|can you|could you|would you|lets|let's)\s+"#,
            #"(?i)^\s*(i will|i'll|i am|i'm|i am going to|i'm going to|i plan to|plan to)\s+"#,
            #"(?i)^\s*(to|for|and|then|next|after|after that|also|between|in|on)\s+"#
        ]
        for p in leadingPatterns {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }

        let trailingPatterns = [
            #"(?i)\bby\b$"#,
            #"(?i)\bat\b$"#,
            #"(?i)\bfor\b$"#,
            #"(?i)\bin\b$"#,
            #"(?i)\bthe\b$"#,
            #"(?i)\bfrom\b$"#,
            #"(?i)\bto\b$"#,
            #"(?i)\buntil\b$"#,
            #"(?i)\btill\b$"#,
            #"(?i)\bbetween\b$"#,
            #"(?i)\bthen\b$"#,
            #"(?i)\bafter\s+that\b$"#,
            #"(?i)\bnext\b$"#,
            #"(?i)\bthank\b$"#,
            #"(?i)\bthan\b$"#,
            #"(?i)\bthem\b$"#
        ]
        for p in trailingPatterns {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }

        t = t.replacingOccurrences(of: #"[\(\)\[\]\{\}]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip trailing glue words repeatedly (e.g., "study for", "call mom to")
        let trailingGlue = Set(["for", "to", "at", "by", "from", "in", "on", "of", "with", "and", "then"])
        while let last = t.split(separator: " ").last, trailingGlue.contains(String(last).lowercased()) {
            t = t.split(separator: " ").dropLast().joined(separator: " ")
        }

        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter for a clean task title.
        if let first = t.first {
            let head = String(first).uppercased()
            let tail = String(t.dropFirst())
            t = head + tail
        }

        return t
    }
}
