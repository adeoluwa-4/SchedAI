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
        static let ordinalDayWordMap: [String: Int] = [
            "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
            "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
            "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
            "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
            "nineteenth": 19, "twentieth": 20, "twenty first": 21,
            "twenty second": 22, "twenty third": 23, "twenty fourth": 24,
            "twenty fifth": 25, "twenty sixth": 26, "twenty seventh": 27,
            "twenty eighth": 28, "twenty ninth": 29, "thirtieth": 30,
            "thirty first": 31
        ]
        static let ordinalDayWordPattern = #"first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|twenty(?:\s|-)?first|twenty(?:\s|-)?second|twenty(?:\s|-)?third|twenty(?:\s|-)?fourth|twenty(?:\s|-)?fifth|twenty(?:\s|-)?sixth|twenty(?:\s|-)?seventh|twenty(?:\s|-)?eighth|twenty(?:\s|-)?ninth|thirtieth|thirty(?:\s|-)?first"#

        // Recurrence
        static let everyDayRegex = try! NSRegularExpression(pattern: #"(?i)\bevery\s+day\b"#)
        static let everyWeekdayRegex = try! NSRegularExpression(pattern: #"(?i)\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#)
        static let everyWeekdaysRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:every\s+)?weekdays?\b"#)
        static let everyWorkdayRegex = try! NSRegularExpression(pattern: #"(?i)\bevery\s+workdays?\b"#)
        static let everyWeekendRegex = try! NSRegularExpression(pattern: #"(?i)\bevery\s+weekends?\b"#)
        static let classDayShorthandRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:every\s+)?(mwf|m/w/f|mon\s*/\s*wed\s*/\s*fri|tth|t/th|tr|t/r|tu(?:e|es|esday)?\s*/\s*thu(?:r|rs|rsday)?)\b"#
        )
        static let everyMultipleWeekdaysRegex = try! NSRegularExpression(
            pattern: #"(?i)\bevery\s+((?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?:\s*(?:,|and|or)\s*(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?))+)\b"#
        )
        static let monthlyRegexes: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: #"(?i)\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)?\s+of\s+every\s+month\b"#),
            try! NSRegularExpression(pattern: #"(?i)\bevery\s+month(?:\s+on\s+the\s+(\d{1,2})(?:st|nd|rd|th)?)?\b"#),
            try! NSRegularExpression(pattern: #"(?i)\bmonthly(?:\s+on\s+the\s+(\d{1,2})(?:st|nd|rd|th)?)?\b"#)
        ]

        // Spoken clock phrases
        static let halfPastRegex = try! NSRegularExpression(pattern: #"(?i)\bhalf\s+past\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let quarterPastRegex = try! NSRegularExpression(pattern: #"(?i)\bquarter\s+past\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let quarterToRegex = try! NSRegularExpression(pattern: #"(?i)\bquarter\s+to\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let spokenHourMinuteRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(at|around|about|near|by|from|to|until|till|starting|start)\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(oh\s+)?(five|ten|fifteen|twenty|twenty[\s-]?five|thirty|forty[\s-]?five|fifty|fifty[\s-]?five)\b"#
        )

        // Number words in time/duration contexts
        static let timeContextRegex = try! NSRegularExpression(pattern: #"(?i)\b(at|around|about|near|by|from|to|until|till|between)\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#)
        static let durationWordRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:for|take|takes|lasting|lasts|last|about|around)?\s*(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(hours?|hrs?|h|minutes?|mins?|m)\b"#)

        // Chunking
        static let primaryChunkDelimiterRegex = try! NSRegularExpression(
            pattern: #"(?i)\s*(?:;|•|\s-\s|\band\s+then\b|\band\s+after\s+that\b|\bafter\s+that\b|\bafterwards?\b|\blater\b|\bthen\b|\balso\b|\bplus\b)\s*"#
        )
        static let betweenAndRegex = try! NSRegularExpression(pattern: #"(?i)\bbetween\b.*\band\b"#)
        static let andDelimiterRegex = try! NSRegularExpression(pattern: #"(?i)\s+and\s+"#)
        static let timeMarkerSplitRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at|by|around|about|near|until|till)\s+(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?|\d{3,4}|noon|midnight)\b|\b(?:by\s+)?(?:eod|end\s+of\s+day)\b"#)
        static let leadingDurationRegex = try! NSRegularExpression(pattern: #"(?i)^\s*(?:for\s+)?\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|mins?|minutes?)\b"#)
        static let fusedVerbs: [String] = [
            "take", "get", "submit", "upload", "call", "send", "email",
            "make", "write", "review", "read", "record", "edit", "post",
            "do", "play", "eat", "have", "go", "be", "finish", "start",
            "study", "workout", "clean", "cook", "drive", "commute",
            "leave", "arrive", "return", "head", "fly", "land", "attend",
            "visit", "drop", "pick", "turn", "pay", "buy", "grab",
            "practice", "revise", "interview",
            "pack", "prep", "cram", "clock",
            "nap", "sleep",
            "shower",
            "watch",
            "shop", "snack",
            "unpack"
        ]
        static let fusedVerbRegex: NSRegularExpression = {
            let pattern = "(?i)\\b(" + fusedVerbs.joined(separator: "|") + ")\\b"
            return try! NSRegularExpression(pattern: pattern)
        }()
        static let repeatedWordRegex = try! NSRegularExpression(pattern: #"(?i)\b([a-z]+)\s+\1\b"#)

        // Base day extraction
        static let monthDayRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,\s*|\s+)?(\d{4})?\b"#)
        static let numericDateRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b"#)
        static let weekdayPattern = #"mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?"#
        static let dayOfWeekRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?((?:next|this|coming)\s+)?("# + weekdayPattern + #")\b"#)
        static let relativeDayRegex = try! NSRegularExpression(pattern: #"(?i)\bin\s+(\d+)\s*(day|days|week|weeks)\b"#)
        static let relativeFromNowRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(day|days|week|weeks)\s+from\s+now\b"#)
        static let dayAfterTomorrowRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:the\s+)?day\s+after\s+tomorrow\b"#)
        static let weekdayOrdinalRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?("# + weekdayPattern + #")\s+the\s+(\d{1,2})(?:st|nd|rd|th)?\b"#)
        static let weekdayOrdinalWordRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:on\s+)?("# + weekdayPattern + #")\s+the\s+("# + ordinalDayWordPattern + #")\b"#)
        static let tomorrowVariantsRegex = try! NSRegularExpression(pattern: #"(?i)\b(tomorrow|tommorow|tomorow|tmr|tmrw|tommorrow|tommporw)\b"#)
        static let todayTonightRegex = try! NSRegularExpression(pattern: #"(?i)\b(today|tonight)\b"#)
        static let nextMonthRegex = try! NSRegularExpression(pattern: #"(?i)\bnext\s+month\b"#)
        static let nextWeekRegex = try! NSRegularExpression(pattern: #"(?i)\bnext\s+week\b"#)
        static let nextBusinessDayRegex = try! NSRegularExpression(pattern: #"(?i)\bnext\s+(?:business\s+day|workday)\b"#)
        static let laterThisWeekRegex = try! NSRegularExpression(pattern: #"(?i)\blater\s+this\s+week\b"#)
        static let endOfWeekRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:by\s+)?(?:end\s+of\s+week|eow)\b"#)
        static let endOfMonthRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:by\s+)?(?:end\s+of\s+month|eom)\b"#)
        static let weekendRegex = try! NSRegularExpression(pattern: #"(?i)\b((?:this|next|coming)\s+)?weekend\b"#)

        // Relative time
        static let nextWindowRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:in|within|over)\s+(?:the\s+)?next\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#)
        static let nextWindowShortRegex = try! NSRegularExpression(pattern: #"(?i)\bnext\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#)
        static let relativeTimeRegex = try! NSRegularExpression(pattern: #"(?i)\bin\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#)

        // Time ranges / single times
        static let timeRangeRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:(from|between)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:to|and|-)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#)
        static let untilRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#)
        static let time24Regex = try! NSRegularExpression(pattern: #"(?i)\b(0\d|1[3-9]|2[0-3])\s*:\s*([0-5]\d)\b"#)
        static let time12Regex = try! NSRegularExpression(pattern: #"(?i)\b(1[0-2]|0?[1-9])(?::\s*([0-5]\d))?\s*(am|pm)\b"#)
        static let timeColonNoMeridiemRegex = try! NSRegularExpression(pattern: #"(?i)\b(1[0-2]|0?[1-9])\s*:\s*([0-5]\d)\b"#)
        static let timeCompactRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at|around|about|near|by|from|starting|start)\s*(\d{3,4})\b"#)
        static let timeBareHourRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at|around|about|near|by)\s*(\d{1,2})\b(?!\s*(?:h|hr|hrs|hour|hours|min|mins|minute|minutes))"#
        )
        static let midnightRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at\s+|by\s+|around\s+|about\s+|near\s+)?midnight\b"#)
        static let noonRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:at\s+|by\s+|around\s+|about\s+|near\s+)?noon\b"#)
        static let eodRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:by\s+)?(?:eod|end\s+of\s+day)\b"#)

        // Duration parsing
        static let durationForRegex = try! NSRegularExpression(pattern: #"(?i)\bfor\s+(\d+(?:\.\d+)?)\s*(h|hrs?|hours?|m|mins?|minutes?)\b"#)
        static let durationHourHalfRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(h|hrs?|hours?)\b"#)
        static let durationComboRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(h|hrs?|hours?)\s+(\d+)\s*(m|mins?|minutes?)\b"#)
        static let durationMinutesRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(m|mins?|minutes?)\b"#)
        static let durationHoursRegex = try! NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(h|hrs?|hours?)\b"#)
    }

    // MARK: - Public entry point

    private enum ParseLimits {
        static let maxInputCharacters = 4000
        static let maxParsedTasks = 20
        static let maxParsedChunks = 20
    }

    static func parse(_ rawText: String, now: Date = Date()) -> [TaskItem] {
        let input = limitedInput(rawText)
        if shouldUseStepPipeline(input) {
            let planned = parseWithStepPipeline(input, now: now)
            if !planned.isEmpty {
                return planned
            }
        }
        return parseInternal(input, now: now, minConfidence: .medium)
    }

    /// Safer parsing: only schedules times when confidence is high.
    static func parseSafely(_ rawText: String, now: Date = Date()) -> [TaskItem] {
        let input = limitedInput(rawText)
        if shouldUseStepPipeline(input) {
            let planned = parseWithStepPipeline(input, now: now)
            if !planned.isEmpty {
                var safePlanned = planned
                applySafeAmbiguityGuard(to: &safePlanned, rawText: input)
                return safePlanned
            }
        }
        return parseInternal(input, now: now, minConfidence: .high)
    }

    private static func parseInternal(_ rawText: String, now: Date, minConfidence: TimeConfidence) -> [TaskItem] {
        let text = normalize(rawText)
        let chunks = Array(splitIntoChunks(text).prefix(ParseLimits.maxParsedChunks))

        var tasks: [TaskItem] = []
        var dayContext = globalDayContextIfUnambiguous(in: text, now: now)

        for rawChunk in chunks {
            let recResult = detectRecurrence(in: rawChunk)
            let chunk = recResult.cleaned

            if let base = parseChunk(chunk, now: now, minConfidence: minConfidence, inheritedTargetDay: dayContext) {
                dayContext = base.targetDay ?? dayContext
                if let rec = recResult.recurrence {
                    let copies = duplicate(task: base, for: rec, reference: now)
                    tasks.append(contentsOf: copies)
                } else {
                    tasks.append(base)
                }
            }
            if tasks.count >= ParseLimits.maxParsedTasks {
                return Array(tasks.prefix(ParseLimits.maxParsedTasks))
            }
        }

        return Array(tasks.prefix(ParseLimits.maxParsedTasks))
    }

    private static func limitedInput(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > ParseLimits.maxInputCharacters else { return trimmed }
        return String(trimmed.prefix(ParseLimits.maxInputCharacters))
    }

    // MARK: - Step-based pipeline

    private enum StepRegex {
        static let connectorRegex = try! NSRegularExpression(
            pattern: #"(?i)\s*(?:\band\s+then\b|\band\s+after\s+that\b|\bafter\s+that\b|\bafterwards?\b|\blater\b(?!\s+(?:today|tonight|this\s+(?:week|morning|afternoon|evening))\b)(?=\s+[a-z])|\bthen\b|\balso\b|\bplus\b|\bnext\b(?!\s+(?:business\s+day|workday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|day|days|week|month|year|\d+\s*(?:m|min|mins?|minutes?|h|hr|hrs?|hours?)))|\band\b)\s*"#
        )
        static let durationRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:for|take|takes|lasting|lasts|last|about|around)?\s*(?:a\s+)?(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?)\b"#
        )
        static let rangeRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:from\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:till|until|to|-)\s*(?:about|around|near)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        )
        static let explicitTimeRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:at|by|around|about|near)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        )
        static let compactTimeRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:at|by|around|about|near)\s*(\d{3,4})\b"#
        )
        static let untilRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        )
        static let eodRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:by\s+)?(?:eod|end\s+of\s+day)\b"#
        )
        static let bareMeridiemRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))\s*(am|pm)\b"#
        )
        static let bareClockRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(\d{1,2}):(\d{2})\b"#
        )
        static let durationThenActionRangeRegex = try! NSRegularExpression(
            pattern: #"(?i)^(.*?\bfor\s+\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|min|mins|minutes?)\b)\s+([a-z].*\b\d{1,2}\s*(?:till|to|-)\s*\d{1,2}\b.*)$"#
        )
        static let rangeAndDurationCleanupRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:from\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:till|until|to|-)\s*(?:about|around|near)?\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b|\b(?:at|by|around|about|near|until|till)\s*(?:\d{1,2}(?::\d{2})?|\d{3,4})\s*(?:am|pm)?\b|\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b|\b(?:by\s+)?(?:eod|end\s+of\s+day)\b|\b(?:for|take|takes|lasting|lasts|last|about|around)?\s*(?:a\s+)?\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|min|mins|minutes?)\b|\b(?:(?:at|by|around|about|near|until|till)\s+)?(?:midnight|noon)\b"#
        )
        static let relativeWindowRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:in|within|over)\s+(?:the\s+)?next\s+(\d+(?:\.\d+)?)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#
        )
        static let relativeOffsetRegex = try! NSRegularExpression(
            pattern: #"(?i)\bin\s+(\d+(?:\.\d+)?)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\b"#
        )
        static let relativeDatePhraseRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:(?:the\s+)?day\s+after\s+tomorrow|today|tonight|tomorrow|tom|tommorow|tomorow|tommorrow|tmrw|tommporw|next\s+(?:business\s+day|workday)|later\s+this\s+week|this\s+weekend|next\s+weekend|coming\s+weekend|weekend|next\s+month|next\s+week|end\s+of\s+week|eow|end\s+of\s+month|eom|next\s+year|next\s+(?:"# + Cache.weekdayPattern + #")|this\s+(?:"# + Cache.weekdayPattern + #")|coming\s+(?:"# + Cache.weekdayPattern + #")|\d+\s*(?:day|days|week|weeks)\s+from\s+now|in\s+\d+\s*(?:day|days|week|weeks)|(?:on\s+)?(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?(?:,\s*\d{4})?|(?:on\s+)?\d{1,2}\/\d{1,2}(?:\/\d{2,4})?|(?:on\s+)?(?:"# + Cache.weekdayPattern + #")\s+the\s+(?:"# + Cache.ordinalDayWordPattern + #")|(?:on\s+)?(?:"# + Cache.weekdayPattern + #")\s+the\s+\d{1,2}(?:st|nd|rd|th)?|(?:on\s+)?(?:"# + Cache.weekdayPattern + #"))\b"#
        )
        static let relativeWeekdayOrdinalWordPhraseRegex = try! NSRegularExpression(
            pattern: #"(?i)\b(?:on\s+)?(?:"# + Cache.weekdayPattern + #")\s+the\s+("# + Cache.ordinalDayWordPattern + #")\b"#
        )
    }

    static func normalizeInput(_ text: String) -> String {
        normalize(text)
    }

    static func splitListEntries(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        chunks = chunks.flatMap { splitFusedActions($0) }

        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func hasExplicitDayReference(_ text: String, now: Date = Date()) -> Bool {
        extractBaseDay(from: normalizeInput(text), now: now).hasExplicitDay
    }

    static func extractTimes(from text: String) -> (start: Date?, end: Date?, duration: Int?) {
        let result = extractTimes(from: text, referenceDate: Date(), previousTaskStart: nil, globalContext: text)
        return (result.start, result.end, result.duration)
    }

    private static func globalDayContextIfUnambiguous(in rawText: String, now: Date) -> Date? {
        let normalized = normalizeInput(rawText)
        let first = extractBaseDay(from: normalized, now: now)
        guard first.hasExplicitDay, let baseDay = first.baseDay else { return nil }

        let second = extractBaseDay(from: first.cleaned, now: now)
        guard !second.hasExplicitDay else { return nil }

        return Calendar.current.startOfDay(for: baseDay)
    }

    private static func shouldUseStepPipeline(_ rawText: String) -> Bool {
        rawText.range(
            of: #"(?i)\b(and|then|after\s+that|afterwards?|later|also|plus|next)\b|\b\d{1,2}(?::\d{2})?\s*(?:till|to|-)\s*\d{1,2}(?::\d{2})?\b|\bmidnight\b|\bnoon\b|\b(?:breakfast|lunch|dinner|supper|bed|sleep|study|homework|laundry|gym|workout|play|meeting|practice|appointment|class|game|call|email|text|pick\s+up|drop\s+off)\b.*\b(?:at|around|about|near|by)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseWithStepPipeline(_ rawText: String, now: Date) -> [TaskItem] {
        let chunks = Array(splitTasks(rawText).prefix(ParseLimits.maxParsedChunks))
        guard !chunks.isEmpty else { return [] }

        var tasks: [TaskItem] = []
        var previousTaskStart: Date? = nil
        var previousTaskTitle: String? = nil
        var dayContext = globalDayContextIfUnambiguous(in: rawText, now: now)
        let globalContext = normalizeInput(rawText)

        for chunk in chunks {
            let recResult = detectRecurrence(in: chunk)
            let parsedChunk = recResult.cleaned

            let timing = extractTimes(
                from: parsedChunk,
                referenceDate: now,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            let priorityResult = extractPriority(from: parsedChunk)
            let title = carrySharedActionTitle(
                extractStepTitle(from: priorityResult.cleaned),
                from: priorityResult.cleaned,
                previousTitle: previousTaskTitle
            )
            guard !title.isEmpty else { continue }

            let estimated = max(5, timing.duration ?? 30)
            let start = timing.start
            var end = timing.end
            let initialTargetDay = timing.targetDay
                ?? start.map { Calendar.current.startOfDay(for: $0) }
                ?? dayContext
            let preferredWindow = preferredWindowIfVague(
                in: parsedChunk,
                targetDay: initialTargetDay,
                now: now
            )
            let targetDay = initialTargetDay
                ?? preferredWindow.map { Calendar.current.startOfDay(for: $0.start) }

            if let start, end == nil {
                end = Calendar.current.date(byAdding: .minute, value: estimated, to: start)
            }

            let isDeadlineOnly = parsedChunk.range(
                of: #"(?i)\bby\s+(?:\d|eod|end\s+of\s+day|midnight|noon)"#,
                options: .regularExpression
            ) != nil
            if !isDeadlineOnly {
                if let end {
                    previousTaskStart = end
                } else if let start {
                    previousTaskStart = start
                }
            }
            if let targetDay {
                dayContext = targetDay
            }
            previousTaskTitle = title

            let task = TaskItem(
                title: title,
                estimatedMinutes: estimated,
                priority: priorityResult.priority,
                isPinned: start != nil && timing.isExplicitTime,
                targetDay: targetDay,
                scheduledStart: start,
                scheduledEnd: end,
                preferredStart: start == nil ? preferredWindow?.start : nil,
                preferredEnd: start == nil ? preferredWindow?.end : nil
            )

            if let rec = recResult.recurrence {
                let copies = duplicate(task: task, for: rec, reference: now)
                tasks.append(contentsOf: copies)
            } else {
                tasks.append(task)
            }
            if tasks.count >= ParseLimits.maxParsedTasks {
                break
            }
        }

        enforceNonOverlappingSchedule(&tasks)
        return Array(tasks.prefix(ParseLimits.maxParsedTasks))
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

    private static func extractTimes(
        from text: String,
        referenceDate: Date,
        previousTaskStart: Date?,
        globalContext: String
    ) -> (start: Date?, end: Date?, duration: Int?, isExplicitTime: Bool, targetDay: Date?) {
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
        let extractedTargetDay = dayResult.baseDay.map { calendar.startOfDay(for: $0) }

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
            return (start, end, max(5, minutes), true, calendar.startOfDay(for: start))
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
            let target = start.map { calendar.startOfDay(for: $0) } ?? extractedTargetDay
            return (start, nil, durationMinutes, true, target)
        }

        if StepRegex.eodRegex.firstMatch(in: working, range: fullRange) != nil {
            let start = buildDate(hour24: 17, minute: 0)
            let end = start.flatMap { calendar.date(byAdding: .minute, value: max(5, durationMinutes ?? 30), to: $0) }
            let target = start.map { calendar.startOfDay(for: $0) } ?? extractedTargetDay
            return (start, end, durationMinutes, true, target)
        }

        if let rangeMatch = StepRegex.rangeRegex.firstMatch(in: working, range: fullRange) {
            let sh = Int(ns.substring(with: rangeMatch.range(at: 1))) ?? 0
            let sm = (rangeMatch.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: rangeMatch.range(at: 2))) ?? 0) : 0
            let sap = (rangeMatch.range(at: 3).location != NSNotFound) ? ns.substring(with: rangeMatch.range(at: 3)).lowercased() : nil

            let eh = Int(ns.substring(with: rangeMatch.range(at: 4))) ?? 0
            let em = (rangeMatch.range(at: 5).location != NSNotFound) ? (Int(ns.substring(with: rangeMatch.range(at: 5))) ?? 0) : 0
            let eap = (rangeMatch.range(at: 6).location != NSNotFound) ? ns.substring(with: rangeMatch.range(at: 6)).lowercased() : nil

            let startHour = resolveHour(
                rawHour: sh,
                minute: sm,
                ampm: sap,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            var endHour = resolveHour(
                rawHour: eh,
                minute: em,
                ampm: eap ?? sap,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
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
            let resolvedTarget = start.map { calendar.startOfDay(for: $0) } ?? extractedTargetDay
            return (start, end, durationMinutes ?? computedDuration, true, resolvedTarget)
        }

        if let untilMatch = StepRegex.untilRegex.firstMatch(in: working, range: fullRange) {
            let h = Int(ns.substring(with: untilMatch.range(at: 1))) ?? 0
            let m = (untilMatch.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: untilMatch.range(at: 2))) ?? 0) : 0
            let ap = (untilMatch.range(at: 3).location != NSNotFound) ? ns.substring(with: untilMatch.range(at: 3)).lowercased() : nil
            let hour24 = resolveHour(
                rawHour: h,
                minute: m,
                ampm: ap,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            var end = buildDate(hour24: hour24, minute: m)

            if !hasExplicitDay, let prev = previousTaskStart, let e = end, e <= prev {
                end = calendar.date(byAdding: .day, value: 1, to: e)
            }

            let start: Date?
            if let end, let durationMinutes {
                start = calendar.date(byAdding: .minute, value: -max(5, durationMinutes), to: end)
            } else {
                start = previousTaskStart
            }

            let resolvedTarget = start.map { calendar.startOfDay(for: $0) } ?? extractedTargetDay
            return (start, end, durationMinutes, true, resolvedTarget)
        }

        var start: Date? = nil
        var explicitTime = false

        if let explicit = StepRegex.explicitTimeRegex.firstMatch(in: working, range: fullRange) {
            let h = Int(ns.substring(with: explicit.range(at: 1))) ?? 0
            let m = (explicit.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: explicit.range(at: 2))) ?? 0) : 0
            let ap = (explicit.range(at: 3).location != NSNotFound) ? ns.substring(with: explicit.range(at: 3)).lowercased() : nil
            let hour24 = resolveHour(
                rawHour: h,
                minute: m,
                ampm: ap,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            start = buildDate(hour24: hour24, minute: m)
            explicitTime = true
        } else if let compact = StepRegex.compactTimeRegex.firstMatch(in: working, range: fullRange),
                  let (h, m) = parseCompactTime(ns.substring(with: compact.range(at: 1))) {
            let hour24 = resolveHour(
                rawHour: h,
                minute: m,
                ampm: nil,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            start = buildDate(hour24: hour24, minute: m)
            explicitTime = true
        } else if let bareClock = StepRegex.bareClockRegex.firstMatch(in: working, range: fullRange) {
            let h: Int
            let m: Int
            let ap: String?
            if bareClock.range(at: 1).location != NSNotFound {
                h = Int(ns.substring(with: bareClock.range(at: 1))) ?? 0
                m = bareClock.range(at: 2).location != NSNotFound ? (Int(ns.substring(with: bareClock.range(at: 2))) ?? 0) : 0
                ap = ns.substring(with: bareClock.range(at: 3)).lowercased()
            } else {
                h = Int(ns.substring(with: bareClock.range(at: 4))) ?? 0
                m = Int(ns.substring(with: bareClock.range(at: 5))) ?? 0
                ap = nil
            }
            let hour24 = resolveHour(
                rawHour: h,
                minute: m,
                ampm: ap,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            start = buildDate(hour24: hour24, minute: m)
            explicitTime = true
        } else if let bare = StepRegex.bareMeridiemRegex.firstMatch(in: working, range: fullRange) {
            let h = Int(ns.substring(with: bare.range(at: 1))) ?? 0
            let m = (bare.range(at: 2).location != NSNotFound) ? (Int(ns.substring(with: bare.range(at: 2))) ?? 0) : 0
            let ap = ns.substring(with: bare.range(at: 3)).lowercased()
            let hour24 = resolveHour(
                rawHour: h,
                minute: m,
                ampm: ap,
                context: working,
                previousTaskStart: previousTaskStart,
                globalContext: globalContext
            )
            start = buildDate(hour24: hour24, minute: m)
            explicitTime = true
        }

        let lower = working.lowercased()
        let beforeBedContext = lower.contains("before bed") || lower.contains("before sleep")
        let mealRelativeContext = lower.range(
            of: #"(?i)\b(?:before|after)\s+(?:breakfast|lunch|dinner|supper)\b"#,
            options: .regularExpression
        ) != nil
        if start == nil {
            if !mealRelativeContext, lower.contains("breakfast") {
                start = buildDate(hour24: 8, minute: 0)
            } else if !mealRelativeContext, lower.contains("lunch") {
                start = buildDate(hour24: 12, minute: 0)
            } else if !mealRelativeContext, lower.contains("dinner") {
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

        let resolvedTarget = start.map { calendar.startOfDay(for: $0) } ?? extractedTargetDay
        return (start, end, durationMinutes, explicitTime, resolvedTarget)
    }

    private static func resolveHour(
        rawHour: Int,
        minute: Int,
        ampm: String?,
        context: String,
        previousTaskStart: Date?,
        globalContext: String
    ) -> Int {
        guard (0...23).contains(rawHour) else { return 0 }
        if rawHour == 0 { return 0 }
        if rawHour > 12 { return rawHour }
        let hour = rawHour
        if let ampm {
            if ampm == "am" { return (hour == 12) ? 0 : hour }
            return (hour == 12) ? 12 : hour + 12
        }

        let local = context.lowercased()
        let global = globalContext.lowercased()

        if local.contains("breakfast") || local.contains("morning") {
            return (hour == 12) ? 8 : hour
        }
        if local.contains("lunch") || local.contains("afternoon") {
            return (hour == 12) ? 12 : ((hour <= 6) ? hour + 12 : hour)
        }
        if local.contains("dinner") || local.contains("supper") {
            return (hour == 12) ? 19 : ((hour <= 11) ? hour + 12 : hour)
        }
        if local.contains("evening") || local.contains("tonight") || local.contains("night") {
            return (hour == 12) ? 12 : hour + 12
        }
        if local.contains("bed") || local.contains("sleep") {
            if hour == 12 { return 0 }
            if hour <= 5 { return hour }
            return hour + 12
        }

        if let previousTaskStart {
            let cal = Calendar.current
            let prevHour = cal.component(.hour, from: previousTaskStart)
            let prevMinute = cal.component(.minute, from: previousTaskStart)
            let candidateMinuteOfDay = hour * 60 + minute
            let previousMinuteOfDay = prevHour * 60 + prevMinute

            if prevHour >= 12, hour <= 11 {
                return (hour == 12) ? 12 : hour + 12
            }

            if prevHour < 12, hour <= 11 {
                return candidateMinuteOfDay >= previousMinuteOfDay ? hour : hour + 12
            }
        }

        let merged = local + " " + global
        let hasPmSignal = merged.range(of: #"\b\d{1,2}(?::\d{2})?\s*pm\b"#, options: .regularExpression) != nil
            || merged.contains("dinner")
            || merged.contains("supper")
            || merged.contains("tonight")
            || merged.contains("evening")
            || merged.contains("night")
        if hasPmSignal, hour <= 11 {
            return (hour == 12) ? 12 : hour + 12
        }

        let deadlineSignal = local.range(
            of: #"(?i)\b(?:due|deadline)\b|\bby\s+\d{1,2}"#,
            options: .regularExpression
        ) != nil
        if deadlineSignal, (9...11).contains(hour) {
            return hour + 12
        }

        // Ambiguous productivity/social actions default to PM for low hours (e.g. "study at 4").
        let likelyPmWords = [
            "study", "homework", "assignment", "work", "laundry", "gym", "workout",
            "exercise", "practice", "review", "meeting", "class", "play", "game",
            "call", "text", "email", "meet", "appointment", "dentist", "doctor", "coach",
            "club", "tryout", "movie", "event", "practice", "errand", "groceries",
            "interview", "mall", "office hours", "shift", "orientation", "lab",
            "exam", "test", "quiz", "midterm", "final", "rehearsal", "reading", "bible", "devotional",
            "pick up", "drop off", "dinner", "lunch", "eat"
        ]
        if hour <= 8, likelyPmWords.contains(where: local.contains) {
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
        stripped = StepRegex.relativeWeekdayOrdinalWordPhraseRegex.stringByReplacingMatches(
            in: stripped,
            range: NSRange(location: 0, length: (stripped as NSString).length),
            withTemplate: " "
        )
        stripped = stripped.replacingOccurrences(of: #"(?i)\bbefore\s+(?:bed|sleep)\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\b(?:later today|later|first thing(?:\s+in\s+the\s+morning)?|this morning|morning|this afternoon|afternoon|this evening|evening|tonight|night)\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\b(?:before|after)\s+(?:work|class|school)\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\b(?:before|after)\s+(?:breakfast|lunch|dinner|supper)\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\b(?:due|deadline)\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bbetween\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bin\s+the\s+next\b"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bfor\s+walk\b"#, with: "for a walk", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"(?i)\bgo\s+walk\b"#, with: "go for a walk", options: .regularExpression)
        return cleanedTitle(from: stripped)
    }

    private static func carrySharedActionTitle(_ title: String, from rawChunk: String, previousTitle: String?) -> String {
        let chunk = normalizeInput(rawChunk).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard chunk.hasPrefix("for "), let previousTitle else { return title }

        let previous = previousTitle.lowercased()
        let reusablePrefixes = ["enroll for", "register for", "sign up for", "apply for"]
        guard let prefix = reusablePrefixes.first(where: { previous.hasPrefix($0 + " ") }) else {
            return title
        }

        return cleanedTitle(from: "\(prefix) \(title)")
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
                if tasks[i].isPinned { continue }
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
            of: #"\b(?:breakfast|lunch|dinner|supper|bed|sleep|midnight|noon|morning|afternoon|evening|tonight|today|tomorrow|interview|appointment|mall|shift|office\s+hours|in\s+\d+\s*(?:day|days|week|weeks)|\d+\s*(?:day|days|week|weeks)\s+from\s+now|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|year)|this\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|coming\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\/\d{1,2}\b|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#,
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
        case weeklyMany(weekdays: [Int], countPerWeekday: Int)
        case monthly(day: Int, count: Int)
    }

    private enum RecurrenceDefaults {
        // Keep recurrence expansion bounded for offline parsing performance.
        static let dailyCount = 30
        static let weeklyCount = 12
        static let monthlyCount = 12
    }

    private static func detectRecurrence(in text: String) -> (recurrence: Recurrence?, cleaned: String) {
        var working = text
        let ns = working as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        if let match = Cache.everyWeekdaysRegex.firstMatch(in: working, range: fullRange) {
            if let r = Range(match.range, in: working) { working.removeSubrange(r) }
            return (.weeklyMany(weekdays: [2, 3, 4, 5, 6], countPerWeekday: 4), working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let match = Cache.everyWorkdayRegex.firstMatch(in: working, range: fullRange) {
            if let r = Range(match.range, in: working) { working.removeSubrange(r) }
            return (.weeklyMany(weekdays: [2, 3, 4, 5, 6], countPerWeekday: 4), working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let match = Cache.everyWeekendRegex.firstMatch(in: working, range: fullRange) {
            if let r = Range(match.range, in: working) { working.removeSubrange(r) }
            return (.weeklyMany(weekdays: [7, 1], countPerWeekday: 6), working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let match = Cache.classDayShorthandRegex.firstMatch(in: working, range: fullRange),
           match.range(at: 1).location != NSNotFound {
            let shorthand = ns.substring(with: match.range(at: 1))
            if let weekdays = classWeekdays(for: shorthand) {
                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return (.weeklyMany(weekdays: weekdays, countPerWeekday: RecurrenceDefaults.weeklyCount), working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if let match = Cache.everyMultipleWeekdaysRegex.firstMatch(in: working, range: fullRange),
           match.range(at: 1).location != NSNotFound {
            let rawDays = ns.substring(with: match.range(at: 1))
            let weekdays = weekdayIndexes(in: rawDays)
            if weekdays.count > 1 {
                if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                return (.weeklyMany(weekdays: weekdays, countPerWeekday: RecurrenceDefaults.weeklyCount), working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Daily: "every day"
        if let match = Cache.everyDayRegex.firstMatch(in: working, range: fullRange) {
            if let r = Range(match.range, in: working) { working.removeSubrange(r) }
            return (.daily(count: RecurrenceDefaults.dailyCount), working.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Weekly: "every thursday"
        if let match = Cache.everyWeekdayRegex.firstMatch(in: working, range: fullRange) {
            let dayName = ns.substring(with: match.range(at: 1)).lowercased()
                if let weekday = weekdayIndex(for: dayName) {
                    if let r = Range(match.range, in: working) { working.removeSubrange(r) }
                    return (.weekly(weekday: weekday, count: RecurrenceDefaults.weeklyCount), working.trimmingCharacters(in: .whitespacesAndNewlines))
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
                return (.monthly(day: max(1, min(31, day)), count: RecurrenceDefaults.monthlyCount), working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return (nil, text)
    }

    private static func duplicate(task base: TaskItem, for rec: Recurrence, reference now: Date) -> [TaskItem] {
        let cal = Calendar.current

        func withDate(_ day: Date, from base: TaskItem) -> TaskItem {
            var t = base
            t.targetDay = cal.startOfDay(for: day)
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
            if cal.isDate(day, inSameDayAs: now), let start = base.scheduledStart {
                let timeComps = cal.dateComponents([.hour, .minute, .second], from: start)
                var dayComps = cal.dateComponents([.year, .month, .day], from: day)
                dayComps.hour = timeComps.hour
                dayComps.minute = timeComps.minute
                dayComps.second = timeComps.second
                if let candidateToday = cal.date(from: dayComps), candidateToday <= now {
                    day = cal.date(byAdding: .day, value: 7, to: day) ?? day
                }
            }
            for i in 0..<count {
                if let d = cal.date(byAdding: .day, value: i * 7, to: cal.startOfDay(for: day)) {
                    out.append(withDate(d, from: base))
                }
            }
        case .weeklyMany(let weekdays, let countPerWeekday):
            for weekday in weekdays {
                var day = now
                while cal.component(.weekday, from: day) != weekday {
                    day = cal.date(byAdding: .day, value: 1, to: day) ?? day
                }
                if cal.isDate(day, inSameDayAs: now), let start = base.scheduledStart {
                    let timeComps = cal.dateComponents([.hour, .minute, .second], from: start)
                    var dayComps = cal.dateComponents([.year, .month, .day], from: day)
                    dayComps.hour = timeComps.hour
                    dayComps.minute = timeComps.minute
                    dayComps.second = timeComps.second
                    if let candidateToday = cal.date(from: dayComps), candidateToday <= now {
                        day = cal.date(byAdding: .day, value: 7, to: day) ?? day
                    }
                }
                for i in 0..<countPerWeekday {
                    if let d = cal.date(byAdding: .day, value: i * 7, to: cal.startOfDay(for: day)) {
                        out.append(withDate(d, from: base))
                    }
                }
            }
            out.sort { ($0.scheduledStart ?? $0.targetDay ?? now) < ($1.scheduledStart ?? $1.targetDay ?? now) }
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
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        s = s.replacingOccurrences(of: #"(?i)\bturn\s+nike\b"#, with: "tonight", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\btonike\b"#, with: "tonight", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bto\s+night\b"#, with: "tonight", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\band\s+after\s+that\b"#, with: " after that ", options: .regularExpression)

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
        s = s.replacingOccurrences(of: #"(?i)\btmr\b"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\btom\b(?=\s+(?:morning|afternoon|evening|night|noon|midnight|(?:at|around|about|near|by)\s+|\d))"#, with: "tomorrow", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bwknd\b"#, with: "weekend", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bhw\b"#, with: "homework", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bappt\b\.?"#, with: "appointment", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bappointmnet\b"#, with: "appointment", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bassignmnet\b"#, with: "assignment", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bmid\s*term\b"#, with: "midterm", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(at|around|about|near|by)\s+like\s+"#, with: "$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+@\s+"#, with: " at ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2}(?::\d{2})?)\s*-?ish\b"#, with: "$1", options: .regularExpression)

        // Convert "7;30" -> "7:30"
        s = s.replacingOccurrences(of: #"(\d)\s*;\s*(\d{2})"#, with: "$1:$2", options: .regularExpression)

        // Convert "7.30" -> "7:30"
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2})\s*\.\s*(\d{2})\b"#, with: "$1:$2", options: .regularExpression)

        // Normalize "a.m." / "p.m." to am/pm
        s = s.replacingOccurrences(of: #"(?i)\ba\.?\s*m\.?\b"#, with: "am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bp\.?\s*m\.?\b"#, with: "pm", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2}):(\d{2})\s*a\b"#, with: "$1:$2am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2}):(\d{2})\s*p\b"#, with: "$1:$2pm", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2})\s*a\b"#, with: "$1am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(\d{1,2})\s*p\b"#, with: "$1pm", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?i)\bevery\s+("# + Cache.weekdayPattern + #")\s+and\s+("# + Cache.weekdayPattern + #")\b"#,
            with: "every $1, $2",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: #"(?i)\bmidnight\b"#, with: "12 am", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bnoon\b"#, with: "12 pm", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?i)\bbetween\s+(\d{1,2}(?::\d{2})?)\s+and\s+(\d{1,2}(?::\d{2})?)\b"#,
            with: "from $1 to $2",
            options: .regularExpression
        )

        // Convert "half past six" -> "6:30", etc
        s = normalizeSpokenClockPhrases(s)
        s = s.replacingOccurrences(of: #"(?i)\b(?:an?|one)\s+hour\s+and\s+a\s+half\b"#, with: "1.5 hours", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(?:an?|one)\s+and\s+a\s+half\s+hours?\b"#, with: "1.5 hours", options: .regularExpression)

        let numberWords: [String: String] = [
            "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
            "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
            "eleven": "11", "twelve": "12"
        ]
        for (word, digit) in numberWords {
            s = s.replacingOccurrences(of: #"(?i)\b\#(word)\b"#, with: digit, options: .regularExpression)
        }

        // Convert spelled-out hours in time contexts: "at six", "from three", etc
        s = replaceNumberWordsInTimeContexts(s)

        // Convert spelled-out duration numbers: "two hours", "three minutes"
        s = replaceNumberWordsInDurationContexts(s)
        s = s.replacingOccurrences(
            of: #"(?i)\b(?:head|heading)\s+out\s+(?:the\s+)?house\s+by\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+to\s+go\s+to\s+church\s+be\s+back\s+home\s+(?:around|about|near|by|at)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#,
            with: "church from $1 to $2",
            options: .regularExpression
        )
        s = collapseRepeatedWords(in: s)

        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return s
    }

    private static func normalizeSpokenClockPhrases(_ input: String) -> String {
        var s = input

        let wordToHour = Cache.numberWordMap
        let minuteWords: [String: Int] = [
            "five": 5,
            "ten": 10,
            "fifteen": 15,
            "twenty": 20,
            "twenty five": 25,
            "twenty-five": 25,
            "thirty": 30,
            "forty five": 45,
            "forty-five": 45,
            "fifty": 50,
            "fifty five": 55,
            "fifty-five": 55
        ]

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

        replaceAll(Cache.spokenHourMinuteRegex) { m, ns in
            let marker = ns.substring(with: m.range(at: 1)).lowercased()
            let hourWord = ns.substring(with: m.range(at: 2)).lowercased()
            let minuteWord = ns.substring(with: m.range(at: 4))
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let h = wordToHour[hourWord] ?? 0
            let minute = minuteWords[minuteWord] ?? 0
            return "\(marker) \(h):\(String(format: "%02d", minute))"
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

    private static func collapseRepeatedWords(in input: String) -> String {
        var current = input
        for _ in 0..<3 {
            let ns = current as NSString
            let next = Cache.repeatedWordRegex.stringByReplacingMatches(
                in: current,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "$1"
            )
            if next == current { break }
            current = next
        }
        return current
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

        // Don’t try to split chunks that still look like they contain a time range.
        let hasFromToClockRange = lower.range(
            of: #"\bfrom\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:to|-)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b"#,
            options: .regularExpression
        ) != nil
        if hasFromToClockRange || lower.contains(" between ") || lower.contains(" until ") || lower.contains(" till ") {
            return [s]
        }

        let ns = s as NSString

        // Find verb starts
        let regex = Cache.fusedVerbRegex
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.count < 2 { return [s] }

        let noBoundaryBefore = Set([
            "a", "an", "the", "to", "for", "with", "in", "on", "of", "from",
            "my", "your", "his", "her", "our", "their", "this", "that",
            "min", "mins", "minute", "minutes", "hour", "hours", "hr", "hrs"
        ])

        func previousToken(before location: Int) -> String? {
            let prefix = ns.substring(with: NSRange(location: 0, length: max(0, location)))
            let tokens = prefix.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return tokens.last.map { String($0).lowercased() }
        }

        func isDestinationPhraseBoundary(_ word: String, before location: Int) -> Bool {
            let nounLikeActions = Set(["meeting", "practice", "workout", "snack", "shop"])
            guard nounLikeActions.contains(word) else { return false }

            let prefix = ns.substring(with: NSRange(location: 0, length: max(0, location)))
            return prefix.range(
                of: #"(?i)\b(?:go|drive|commute|walk|head|headed|going)\s+to\s+(?:[a-z0-9]+\s+){0,4}$"#,
                options: .regularExpression
            ) != nil
        }

        func isObjectPhraseBoundary(_ word: String, before location: Int) -> Bool {
            let objectLikeActions = Set(["email", "call", "review"])
            guard objectLikeActions.contains(word) else { return false }

            let prefix = ns.substring(with: NSRange(location: 0, length: max(0, location)))
            return prefix.range(
                of: #"(?i)\b(?:send|write|draft|make)\s+(?:[a-z0-9]+\s+){0,4}$"#,
                options: .regularExpression
            ) != nil
        }

        // Collect verb starts that look like true action boundaries.
        var starts: [Int] = []
        for match in matches {
            let start = match.range.location
            if start == 0 {
                starts.append(start)
                continue
            }
            let word = ns.substring(with: match.range).lowercased()
            if isDestinationPhraseBoundary(word, before: start) { continue }
            if isObjectPhraseBoundary(word, before: start) { continue }
            if let prev = previousToken(before: start) {
                if noBoundaryBefore.contains(prev) { continue }
                if prev.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { continue }
            }
            starts.append(start)
        }
        starts = Array(Set(starts)).sorted()
        if starts.count < 2 { return [s] }

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
        if s.range(of: #"(?i)\bnext\s+(business\s+day|workday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|year)\b"#, options: .regularExpression) != nil {
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

    private static func parseChunk(
        _ chunk: String,
        now: Date,
        minConfidence: TimeConfidence,
        inheritedTargetDay: Date?
    ) -> TaskItem? {
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

        let estimatedMinutes = max(5, minutes ?? 30)

        let priorityResult = extractPriority(from: text)
        let priority = priorityResult.priority
        text = priorityResult.cleaned

        let title = cleanedTitle(from: text)
        guard !title.isEmpty else { return nil }

        let preferredWindow = preferredWindowIfVague(
            in: chunk,
            targetDay: timeResult.targetDay ?? inheritedTargetDay,
            now: now
        )

        // Map parsed time info to TaskItem's scheduling fields.
        // If we have an explicit clock time or a time range, set scheduledStart and scheduledEnd.
        let scheduledStart: Date?
        let scheduledEnd: Date?
        if let start = (timeConfidence >= minConfidence) ? dueDate : nil {
            scheduledStart = start
            scheduledEnd = Calendar.current.date(byAdding: .minute, value: estimatedMinutes, to: start)
        } else {
            scheduledStart = nil
            scheduledEnd = nil
        }

        return TaskItem(
            title: title,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            isPinned: scheduledStart != nil && timeResult.isExplicit,
            targetDay: timeResult.targetDay
                ?? scheduledStart.map { Calendar.current.startOfDay(for: $0) }
                ?? preferredWindow.map { Calendar.current.startOfDay(for: $0.start) }
                ?? inheritedTargetDay,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            preferredStart: scheduledStart == nil ? preferredWindow?.start : nil,
            preferredEnd: scheduledStart == nil ? preferredWindow?.end : nil
        )
    }

    private static func preferredWindowIfVague(in text: String, targetDay: Date?, now: Date) -> (start: Date, end: Date)? {
        if let learned = SchedulingPreferenceStore.learnedWindow(for: text, targetDay: targetDay, now: now) {
            return learned
        }

        let lower = normalizeInput(text).lowercased()
        let hasVagueTime = lower.range(
            of: #"(?i)\b(later today|later|first thing(?:\s+in\s+the\s+morning)?|this morning|morning|this afternoon|afternoon|this evening|evening|night|tonight|before bed|before sleep|before work|after work|before class|after class|before school|after school|before breakfast|after breakfast|before lunch|after lunch|before dinner|after dinner|before supper|after supper|party|prom|formal|dance|kickback|hangout)\b"#,
            options: .regularExpression
        ) != nil
        guard hasVagueTime else { return nil }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: targetDay ?? now)

        func date(hour: Int, minute: Int = 0) -> Date? {
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.date(from: comps)
        }

        func roundedFuture(minutesFromNow: Int) -> Date {
            let raw = calendar.date(byAdding: .minute, value: minutesFromNow, to: now) ?? now.addingTimeInterval(TimeInterval(minutesFromNow * 60))
            return roundUp(raw, toMinutes: 5, calendar: calendar)
        }

        let start: Date?
        let end: Date?

        if lower.range(of: #"(?i)\b(?:party|prom|formal|dance|kickback)\b"#, options: .regularExpression) != nil {
            start = date(hour: 20)
            end = date(hour: 23)
        } else if lower.contains("hangout") {
            start = date(hour: 18)
            end = date(hour: 21)
        } else if lower.contains("first thing") {
            start = date(hour: 8)
            end = date(hour: 10)
        } else if lower.contains("before breakfast") {
            start = date(hour: 6)
            end = date(hour: 8)
        } else if lower.contains("after breakfast") || lower.contains("before lunch") {
            start = date(hour: 10)
            end = date(hour: 12)
        } else if lower.contains("after lunch") {
            start = date(hour: 13)
            end = date(hour: 15)
        } else if lower.contains("before dinner") || lower.contains("before supper") {
            start = date(hour: 16)
            end = date(hour: 18)
        } else if lower.contains("after dinner") || lower.contains("after supper") {
            start = date(hour: 19)
            end = date(hour: 21)
        } else if lower.contains("before work") || lower.contains("before class") || lower.contains("before school") {
            start = date(hour: 7)
            end = date(hour: 9)
        } else if lower.contains("after work") {
            start = date(hour: 17)
            end = date(hour: 20)
        } else if lower.contains("after class") || lower.contains("after school") {
            start = date(hour: 15)
            end = date(hour: 18)
        } else if lower.contains("morning") {
            start = date(hour: 9)
            end = date(hour: 12)
        } else if lower.contains("tonight") || lower.contains("night") || lower.contains("before bed") || lower.contains("before sleep") {
            start = date(hour: 19)
            end = date(hour: 22)
        } else if lower.contains("evening") {
            start = date(hour: 17)
            end = date(hour: 21)
        } else if lower.contains("afternoon") {
            start = date(hour: 13)
            end = date(hour: 17)
        } else {
            let nowHour = calendar.component(.hour, from: now)
            if !calendar.isDate(day, inSameDayAs: now) {
                start = date(hour: 15)
                end = date(hour: 20)
            } else if nowHour < 12 {
                start = date(hour: 15)
                end = date(hour: 20)
            } else if nowHour < 15 {
                start = date(hour: 17)
                end = date(hour: 21)
            } else {
                start = roundedFuture(minutesFromNow: 90)
                end = date(hour: 22)
            }
        }

        guard var windowStart = start, var windowEnd = end else { return nil }
        if calendar.isDate(day, inSameDayAs: now), windowStart <= now {
            windowStart = roundedFuture(minutesFromNow: 60)
        }
        if windowEnd <= windowStart {
            windowEnd = calendar.date(byAdding: .hour, value: 2, to: windowStart) ?? windowStart.addingTimeInterval(7200)
        }
        return (windowStart, windowEnd)
    }

    // MARK: - Time parsing

    private struct TimeParseResult {
        let date: Date?
        let cleaned: String
        let confidence: TimeConfidence
        let durationOverrideMinutes: Int?
        let isExplicit: Bool
        let targetDay: Date?
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
        let explicitTargetDay = dayResult.baseDay.map { calendar.startOfDay(for: $0) }

        // "in the next 30 minutes" → start now (rounded) with duration override
        if let next = extractNextWindow(from: working) {
            working = next.cleaned

            let start = roundUp(now, toMinutes: 5, calendar: calendar)
            return TimeParseResult(date: start,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .high,
                                   durationOverrideMinutes: max(5, next.minutes),
                                   isExplicit: true,
                                   targetDay: calendar.startOfDay(for: start))
        }

        if let rel = extractRelativeTime(from: working, now: now) {
            working = rel.cleaned
            return TimeParseResult(date: rel.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .high,
                                   durationOverrideMinutes: nil,
                                   isExplicit: true,
                                   targetDay: calendar.startOfDay(for: rel.date))
        }

        if let range = extractTimeRange(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = range.cleaned
            return TimeParseResult(date: range.start,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: range.confidence,
                                   durationOverrideMinutes: max(5, range.minutes),
                                   isExplicit: true,
                                   targetDay: calendar.startOfDay(for: range.start))
        }

        if let until = extractUntilTime(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = until.cleaned

            let start = roundUp(now, toMinutes: 5, calendar: calendar)
            return TimeParseResult(date: start,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: until.confidence,
                                   durationOverrideMinutes: max(5, until.minutes),
                                   isExplicit: true,
                                   targetDay: calendar.startOfDay(for: start))
        }

        if let single = extractSingleClockTime(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = single.cleaned
            return TimeParseResult(date: single.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: single.confidence,
                                   durationOverrideMinutes: nil,
                                   isExplicit: true,
                                   targetDay: calendar.startOfDay(for: single.date))
        }

        if let kw = extractKeywordTime(from: working, baseDay: baseDay ?? now, hasExplicitDay: hasExplicitDay, now: now) {
            working = kw.cleaned
            return TimeParseResult(date: kw.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .high,
                                   durationOverrideMinutes: nil,
                                   isExplicit: false,
                                   targetDay: calendar.startOfDay(for: kw.date))
        }

        if let pod = inferPartOfDayIfPresent(from: working, baseDay: baseDay ?? now) {
            working = pod.cleaned
            return TimeParseResult(date: pod.date,
                                   cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                                   confidence: .low,
                                   durationOverrideMinutes: nil,
                                   isExplicit: false,
                                   targetDay: calendar.startOfDay(for: pod.date))
        }

        return TimeParseResult(date: nil,
                               cleaned: working.trimmingCharacters(in: .whitespacesAndNewlines),
                               confidence: .low,
                               durationOverrideMinutes: nil,
                               isExplicit: false,
                               targetDay: explicitTargetDay)
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

        func strictDate(year: Int, month: Int, day: Int) -> Date? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }

            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = 0
            comps.minute = 0

            guard let date = calendar.date(from: comps) else { return nil }
            let resolved = calendar.dateComponents([.year, .month, .day], from: date)
            guard resolved.year == year,
                  resolved.month == month,
                  resolved.day == day else {
                return nil
            }
            return date
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
                    if let date0 = strictDate(year: year, month: month, day: day) {
                        var resolved = date0
                        if yStr == nil && calendar.startOfDay(for: date0) < calendar.startOfDay(for: now) {
                            year += 1
                            guard let future = strictDate(year: year, month: month, day: day) else { return BaseDayResult(baseDay: nil, cleaned: working, hasExplicitDay: false) }
                            resolved = future
                        }
                        baseDay = resolved
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

                    if let date0 = strictDate(year: year, month: m, day: d) {
                        var resolved = date0
                        if yStr == nil && calendar.startOfDay(for: date0) < calendar.startOfDay(for: now) {
                            guard let future = strictDate(year: year + 1, month: m, day: d) else { return BaseDayResult(baseDay: nil, cleaned: working, hasExplicitDay: false) }
                            resolved = future
                        }
                        baseDay = resolved
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
            let regex = Cache.weekdayOrdinalWordRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let dayName = ns.substring(with: match.range(at: 1))
                let ordinal = ns.substring(with: match.range(at: 2))

                if let weekday = weekdayIndex(for: dayName),
                   let dayNum = ordinalDayNumber(from: ordinal),
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
                    if let resolved = dateFor(qualifier: qualifier, weekday: weekday, reference: now) {
                        baseDay = resolved
                        explicitDay = true
                        removeMatch(match.range)
                    }
                }
            }
        }

        if baseDay == nil {
            let regex = Cache.dayAfterTomorrowRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
                explicitDay = true
                removeMatch(match.range)
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

        if baseDay == nil {
            let regex = Cache.todayTonightRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = calendar.startOfDay(for: now)
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
            let regex = Cache.nextBusinessDayRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = nextBusinessDay(after: now)
                explicitDay = baseDay != nil
                removeMatch(match.range)
            }
        }

        if baseDay == nil {
            let regex = Cache.laterThisWeekRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = laterThisWeek(reference: now)
                explicitDay = baseDay != nil
                removeMatch(match.range)
            }
        }

        if baseDay == nil {
            let regex = Cache.endOfMonthRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = endOfMonth(reference: now)
                explicitDay = baseDay != nil
                removeMatch(match.range)
            }
        }

        if baseDay == nil {
            let regex = Cache.weekendRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                let qualifierRange = match.range(at: 1)
                let qualifier = qualifierRange.location != NSNotFound
                    ? ns.substring(with: qualifierRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                baseDay = weekendStart(qualifier: qualifier, reference: now)
                explicitDay = baseDay != nil
                removeMatch(match.range)
            }
        }

        if baseDay == nil {
            let regex = Cache.endOfWeekRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = dateFor(qualifier: nil, weekday: 6, reference: now)
                explicitDay = baseDay != nil
                removeMatch(match.range)
            }
        }

        if baseDay == nil {
            let regex = Cache.nextWeekRegex
            let ns = working as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: working, range: range) {
                baseDay = dateFor(qualifier: "next", weekday: 2, reference: now)
                explicitDay = baseDay != nil
                removeMatch(match.range)
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
        case "sunday", "sun": return 1
        case "monday", "mon": return 2
        case "tuesday", "tue", "tues": return 3
        case "wednesday", "wed": return 4
        case "thursday", "thu", "thur", "thurs": return 5
        case "friday", "fri": return 6
        case "saturday", "sat": return 7
        default: return nil
        }
    }

    private static func weekdayIndexes(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: Cache.weekdayPattern, options: [.caseInsensitive]) else {
            return []
        }

        let ns = text as NSString
        var seen = Set<Int>()
        var indexes: [Int] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            guard let weekday = weekdayIndex(for: token), !seen.contains(weekday) else { continue }
            seen.insert(weekday)
            indexes.append(weekday)
        }
        return indexes
    }

    private static func classWeekdays(for shorthand: String) -> [Int]? {
        let key = shorthand
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "/", with: "")

        switch key {
        case "mwf", "monwedfri":
            return [2, 4, 6]
        case "tth", "tr", "tuethu", "tuesthu", "tuesthurs", "tuesdaythursday":
            return [3, 5]
        default:
            if key.hasPrefix("tue") && key.contains("thu") { return [3, 5] }
            return nil
        }
    }

    private static func ordinalDayNumber(from phrase: String) -> Int? {
        let key = phrase
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Cache.ordinalDayWordMap[key]
    }

    private static func dateFor(qualifier: String?, weekday: Int, reference: Date) -> Date? {
        let cal = Calendar.current
        let refWeekday = cal.component(.weekday, from: reference)
        var delta = (weekday - refWeekday + 7) % 7
        let q = qualifier?.lowercased() ?? ""

        if q.contains("next") {
            delta = (delta == 0) ? 7 : (delta + 7)
        }
        let start = cal.startOfDay(for: reference)
        return cal.date(byAdding: .day, value: delta, to: start)
    }

    private static func weekendStart(qualifier: String?, reference: Date) -> Date? {
        let cal = Calendar.current
        let refStart = cal.startOfDay(for: reference)
        let refWeekday = cal.component(.weekday, from: refStart)
        let q = qualifier?.lowercased() ?? ""
        var delta = (7 - refWeekday + 7) % 7

        if q.contains("next") {
            delta = delta + 7
        } else if delta == 0 {
            delta = 0
        }

        return cal.date(byAdding: .day, value: delta, to: refStart)
    }

    private static func nextBusinessDay(after reference: Date) -> Date? {
        let cal = Calendar.current
        var candidate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: reference))

        while let day = candidate {
            let weekday = cal.component(.weekday, from: day)
            if (2...6).contains(weekday) {
                return day
            }
            candidate = cal.date(byAdding: .day, value: 1, to: day)
        }

        return nil
    }

    private static func laterThisWeek(reference: Date) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: reference)
        if let friday = dateFor(qualifier: nil, weekday: 6, reference: reference), friday > start {
            return friday
        }
        return cal.date(byAdding: .day, value: 1, to: start)
    }

    private static func endOfMonth(reference: Date) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: reference)
        guard let range = cal.range(of: .day, in: .month, for: start) else { return nil }
        var comps = cal.dateComponents([.year, .month], from: start)
        comps.day = range.count
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps)
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
        // A range confidence should reflect its weakest endpoint.
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
                    let confidence: TimeConfidence = isReminderColonClockRequest(context) ? .high : parts.confidence
                    return SingleTimeResult(date: date, cleaned: working, confidence: confidence)
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

    private static func isReminderColonClockRequest(_ context: String) -> Bool {
        let normalized = normalizeInput(context)
        let hasReminderLeadIn = normalized.range(
            of: #"(?i)\b(?:remind me|reminder|(?:don't|dont|do not)\s+let\s+me\s+forget)\b"#,
            options: .regularExpression
        ) != nil
        guard hasReminderLeadIn else { return false }

        return normalized.range(
            of: #"(?i)\b(?:at|around|about|near|by)\s*\d{1,2}\s*:\s*\d{2}\b"#,
            options: .regularExpression
        ) != nil
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
        let likelyDaytimePmWords = [
            "office hours", "interview", "appointment", "mall", "shift",
            "orientation", "career fair", "meeting", "practice", "study session", "lab"
        ]
        let deadlineSignal = ctx.range(
            of: #"(?i)\b(?:due|deadline)\b|\bby\s+\d{1,2}"#,
            options: .regularExpression
        ) != nil

        let wantsAM = morningWords.contains(where: ctx.contains)
        let wantsPM = eveningWords.contains(where: ctx.contains) || nightWords.contains(where: ctx.contains)
        let wantsSleepTime = sleepWords.contains(where: ctx.contains)

        if wantsSleepTime, h <= 5 { return InferredTimeParts(hour24: h, minute: m, confidence: .high) }
        if wantsAM { return InferredTimeParts(hour24: h, minute: m, confidence: .high) }
        if afternoonWords.contains(where: ctx.contains) { return InferredTimeParts(hour24: h + 12, minute: m, confidence: .high) }
        if wantsPM { return InferredTimeParts(hour24: h + 12, minute: m, confidence: .high) }
        if deadlineSignal, (9...11).contains(h) {
            return InferredTimeParts(hour24: h + 12, minute: m, confidence: .high)
        }
        if h <= 8, likelyDaytimePmWords.contains(where: ctx.contains) {
            return InferredTimeParts(hour24: h + 12, minute: m, confidence: .high)
        }

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
        let minutes: Int?
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

        return DurationParseResult(minutes: nil,
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
        let originalTitleText = normalizeInput(text).lowercased()
        let preserveScheduleAction = originalTitleText.range(
            of: #"(?i)^\s*(?:remind me|reminder|(?:don't|dont|do not)\s+let\s+me\s+forget)\b.*\bto\s+schedule\b"#,
            options: .regularExpression
        ) != nil

        let fillers = [
            "i have to", "i need to", "i gotta", "gotta",
            "need to", "have to", "i have", "i need", "i wanna", "i want to",
            "i'm gonna", "im gonna", "i am gonna", "i'm going to", "im going to", "i am going to",
            "gonna", "going to",
            "then", "and then", "after that", "next", "thank", "than", "them"
        ]
        for filler in fillers {
            t = t.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
        }

        // Remove common lead-ins (polite or planning phrases)
        var leadingPatterns = [
            #"(?i)^\s*(please|can you|could you|would you|lets|let's)\s+"#,
            #"(?i)^\s*(?:remind me|reminder)\s+(?:to|about|for)?\s*"#,
            #"(?i)^\s*(?:don't|dont|do not)\s+let\s+me\s+forget\s+(?:to|about|for)?\s*"#,
            #"(?i)^\s*make\s+sure\s+(?:that\s+)?(?:i\s+)?(?:to\s+)?"#,
            #"(?i)^\s*(i will|i'll|i am|i'm|i am going to|i'm going to|i plan to|plan to)\s+"#,
            #"(?i)^\s*(?:i've\s+got|ive\s+got|i\s+ve\s+got|i\s+have\s+got|im|i m|ill|i ll|i'm|i'll|ive|i ve|i've|i\s+am|i\s+will|i\s+should|i\s+need|i\s+have|i\s+got|i\s+want|i\s+wanna|i\s+am\s+supposed\s+to|i'm\s+supposed\s+to|im\s+supposed\s+to)\s+(?:to|a|an|the|my)?\s*"#,
            #"(?i)^\s*there(?:\s+is|'s|s)\s+(?:a|an|the)?\s*"#,
            #"(?i)^\s*there\s+are\s+(?:some|the)?\s*"#,
            #"(?i)^\s*(?:early\s+)?(?:morning|afternoon|evening|tonight|night)\s+"#,
            #"(?i)^\s*been\s+"#,
            #"(?i)^\s*(?:(?:to|for|from|and|then|next|after|after that|also|between|in|on|at|by|around|about|near)\s+)+"#
        ]
        let commandPattern = preserveScheduleAction
            ? #"(?i)^\s*(?:add|put|set up|set|create|book)\s+(?:a|an|the|my|this)?\s*"#
            : #"(?i)^\s*(?:schedule|add|put|set up|set|create|book)\s+(?:a|an|the|my|this)?\s*"#
        leadingPatterns.insert(commandPattern, at: 4)

        for _ in 0..<4 {
            let before = t
            for p in leadingPatterns {
                t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
            }
            if t == before { break }
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
            #"(?i)\btakes?\b$"#,
            #"(?i)\blasts?\b$"#,
            #"(?i)\blasting\b$"#,
            #"(?i)\bthank\b$"#,
            #"(?i)\bthan\b$"#,
            #"(?i)\bthem\b$"#
        ]
        for p in trailingPatterns {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }

        t = t.replacingOccurrences(of: #"[\(\)\[\]\{\}]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)\bgo\s+walk\b"#, with: "go for a walk", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)\b(?:due|deadline)\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let namesAfterWith = capitalizedNamesAfterWith(in: t)
        let namesAfterAction = capitalizedNamesAfterAction(in: t)

        // Strip trailing glue words repeatedly (e.g., "study for", "call mom to")
        let trailingGlue = Set(["for", "to", "at", "by", "from", "in", "on", "of", "with", "and", "then"])
        while let last = t.split(separator: " ").last, trailingGlue.contains(String(last).lowercased()) {
            t = t.split(separator: " ").dropLast().joined(separator: " ")
        }

        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.lowercased()
        t = t.replacingOccurrences(of: #"(?i)\b(do homework)\s+\1\b"#, with: "$1", options: .regularExpression)
        if t == "had to work" {
            t = "head to work"
        }
        t = t.replacingOccurrences(
            of: #"(?i)^.*\bleave\s+(?:the\s+)?house\b"#,
            with: "leave house",
            options: .regularExpression
        )
        t = t.replacingOccurrences(of: #"(?i)\s+for\s+that$"#, with: "", options: .regularExpression)

        if let structured = structuredCalendarTitle(original: originalTitleText, cleaned: t) {
            return structured
        }

        // Keep titles in a predictable sentence case for UI consistency.
        if let first = t.first {
            let head = String(first).uppercased()
            let tail = String(t.dropFirst())
            t = head + tail
        }
        for name in namesAfterWith {
            let escaped = NSRegularExpression.escapedPattern(for: name.lowercased())
            let pattern = #"(?i)\bwith\s+"# + escaped + #"\b"#
            t = t.replacingOccurrences(of: pattern, with: "with \(name)", options: .regularExpression)
        }
        for (action, displayAction, name) in namesAfterAction {
            let escapedAction = NSRegularExpression.escapedPattern(for: action)
            let escapedName = NSRegularExpression.escapedPattern(for: name.lowercased())
            let pattern = #"(?i)\b"# + escapedAction + #"\s+"# + escapedName + #"\b"#
            t = t.replacingOccurrences(of: pattern, with: "\(displayAction) \(name)", options: .regularExpression)
        }

        return t
    }

    private static func capitalizedNamesAfterWith(in text: String) -> [String] {
        let pattern = #"\bwith\s+([A-Z][A-Za-z'-]{1,}(?:\s+[A-Z][A-Za-z'-]{1,})?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private static func capitalizedNamesAfterAction(in text: String) -> [(action: String, displayAction: String, name: String)] {
        let pattern = #"\b(meet|text|call|email)\s+([A-Z][A-Za-z'-]{1,}(?:\s+[A-Z][A-Za-z'-]{1,})?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.range(at: 1).location != NSNotFound,
                  match.range(at: 2).location != NSNotFound else { return nil }
            let action = ns.substring(with: match.range(at: 1)).lowercased()
            let displayAction = action.prefix(1).uppercased() + action.dropFirst()
            return (
                action: action,
                displayAction: String(displayAction),
                name: ns.substring(with: match.range(at: 2))
            )
        }
    }

    private static func structuredCalendarTitle(original: String, cleaned: String) -> String? {
        let title = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title.range(of: #"\bwake\s+up\b"#, options: .regularExpression) != nil {
            return "Wake Up"
        }

        if title.contains("grocery shopping") || title.range(of: #"\bgo\s+grocery\b"#, options: .regularExpression) != nil {
            return "Grocery Shopping"
        }

        if original.contains("gonna do homework")
            || original.contains("i'm doing homework")
            || original.contains("im doing homework")
            || title == "do homework"
            || title.hasPrefix("do homework ")
            || title == "doing homework"
            || title.hasPrefix("doing homework ")
            || title == "homework"
            || title.hasPrefix("homework from") {
            return "Homework"
        }

        if title.contains("meal prep") {
            return "Meal Prep"
        }

        if title.range(of: #"\b(?:head|heading|go)\s+out\s+(?:the\s+)?house\b"#, options: .regularExpression) != nil {
            return "Leave Home"
        }

        if title.contains("go to church") || title == "church" {
            return "Church"
        }

        if title.range(of: #"\bbe\s+back\s+home\b|\breturn\s+home\b"#, options: .regularExpression) != nil {
            return "Return Home"
        }

        if title.range(of: #"\bbe\s+in\s+bed\b|\bgo\s+to\s+bed\b|\bgo\s+sleep\b|\bgo\s+to\s+sleep\b"#, options: .regularExpression) != nil
            || title == "bed"
            || title == "sleep" {
            return "Bedtime"
        }

        return nil
    }
}
