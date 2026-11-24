import Foundation
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Turns syllabus text into course deadlines and class times, entirely on device.
///
/// Dates come from `NSDataDetector` (Apple's own date recognizer) rather than
/// hand-written regex, so formats like "Oct 14", "10/14", "Tuesday, October 14"
/// and "Week 7 (Oct 14)" all work without special cases.
struct SyllabusReader {

    struct Result: Equatable {
        var course: String?
        var deadlines: [CourseDeadline]
        var classes: [ClassMeeting]
    }

    // MARK: - Text extraction

    enum ExtractionError: LocalizedError {
        case unreadablePDF, unreadableImage, noText

        var errorDescription: String? {
            switch self {
            case .unreadablePDF: return "That PDF couldn't be opened."
            case .unreadableImage: return "That photo couldn't be read."
            case .noText: return "No text was found. Try a clearer photo or paste the schedule instead."
            }
        }
    }

    static func text(fromPDF url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadablePDF }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExtractionError.noText }
        return text
    }

    #if canImport(UIKit)
    /// On-device OCR with Vision. Lines come back top to bottom.
    static func text(fromImage image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw ExtractionError.unreadableImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                if text.isEmpty { continuation.resume(throwing: ExtractionError.noText) } else { continuation.resume(returning: text) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif

    // MARK: - Parsing

    static func read(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        let course = detectCourse(in: text)
        let courseName = course ?? "Course"
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var deadlines: [CourseDeadline] = []
        var seen = Set<String>()
        for line in lines {
            guard let found = deadline(in: line, course: courseName, now: now, calendar: calendar) else { continue }
            let key = "\(found.title.lowercased())|\(calendar.startOfDay(for: found.due).timeIntervalSince1970)"
            if seen.insert(key).inserted { deadlines.append(found) }
        }

        let classes = lines.compactMap { classMeeting(in: $0, course: courseName) }
        return Result(
            course: course,
            deadlines: deadlines.sorted { $0.due < $1.due },
            classes: Array(classes.prefix(3))
        )
    }

    /// "CHEM 101", "PSYC-2010", "CS 61A".
    static func detectCourse(in text: String) -> String? {
        let pattern = #"\b([A-Z]{2,5})\s?-?\s?(\d{2,4}[A-Z]?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let letters = ns.substring(with: match.range(at: 1))
            // Skip things that look like times or terms, e.g. "PM 2026" or "FALL 2026".
            if ["AM", "PM", "FALL", "SPRING", "SUMMER", "WINTER", "WEEK", "ROOM", "UNIT"].contains(letters) { continue }
            return "\(letters) \(ns.substring(with: match.range(at: 2)))"
        }
        return nil
    }

    static func kind(of line: String) -> DeadlineKind {
        let l = line.lowercased()
        func has(_ words: [String]) -> Bool {
            words.contains { l.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
        }
        if has(["final exam", "final"]) && !has(["final project", "final paper"]) { return .final }
        if has(["midterm", "exam", "test"]) { return .exam }
        if has(["quiz"]) { return .quiz }
        if has(["paper", "essay", "report", "draft"]) { return .paper }
        if has(["project", "presentation"]) { return .project }
        if has(["lab"]) { return .lab }
        if has(["homework", "hw", "problem set", "pset", "assignment", "worksheet", "due"]) { return .assignment }
        if has(["read", "reading", "chapter", "ch\\."]) { return .reading }
        return .other
    }

    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// "Nov 25", "Friday, Nov 27", "December 4, 2026", "Dec 3 at 11:59 PM", "10/14", "10/14/26 5pm".
    private static let datePhrase = try? NSRegularExpression(pattern: #"""
    (?ix)
    (?:\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?,?\s+)?
    (?:
      \b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?
      |
      \b\d{1,2}/\d{1,2}(?:/\d{2,4})?
    )
    (?:\s*(?:at|@|,|-|–)?\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\s*(?:at|,)?\s*\d{1,2}:\d{2}\b)?
    """#)

    /// The date that a line's deadline is actually on. With several dates
    /// ("Week 14 (Dec 1): Lab report due Dec 3"), prefer the one right after
    /// "due"/"by"/"on", otherwise the last one; the first is often a week label.
    static func datePhraseRange(in line: String) -> NSRange? {
        allDatePhraseRanges(in: line).last { range in
            let prefixStart = max(0, range.location - 8)
            let prefix = (line as NSString).substring(with: NSRange(location: prefixStart, length: range.location - prefixStart))
            return prefix.range(of: #"(?i)\b(due|by|on)\s*$"#, options: .regularExpression) != nil
        } ?? allDatePhraseRanges(in: line).last
    }

    static func allDatePhraseRanges(in line: String) -> [NSRange] {
        datePhrase?.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length)).map(\.range) ?? []
    }

    private static func deadline(in line: String, course: String, now: Date, calendar: Calendar) -> CourseDeadline? {
        let kind = kind(of: line)
        // Lecture topics ("Sep 4 – Intro to cells") have dates too. Keep a line
        // only if it names something graded or explicitly says "due".
        guard kind != .other else { return nil }
        guard let detector = dateDetector else { return nil }
        let ns = line as NSString
        // Find the date phrase first with a strict pattern, then let
        // NSDataDetector read only that phrase. Run on the whole line, the
        // detector pulls in nearby numbers ("Problem Set 7 due Nov 25") and
        // misreads words like "due".
        guard let phraseRange = datePhraseRange(in: line) else { return nil }
        let phrase = ns.substring(with: phraseRange)
        guard let match = detector.firstMatch(in: phrase, range: NSRange(location: 0, length: (phrase as NSString).length)),
              var date = match.date else { return nil }

        // A syllabus is about the coming months. If a yearless date lands far in
        // the past, it belongs to next year (e.g. reading "Jan 20" in November).
        if date < calendar.date(byAdding: .day, value: -60, to: now) ?? now,
           let shifted = calendar.date(byAdding: .year, value: 1, to: date) {
            date = shifted
        }

        let mentionsTime = phrase.range(of: #"(?i)\b\d{1,2}(:\d{2})?\s*(am|pm)\b|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b"#, options: .regularExpression) != nil
        let day = calendar.startOfDay(for: date)
        let due: Date
        if mentionsTime {
            due = date
        } else if kind == .final || kind == .exam || kind == .quiz {
            due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day   // placeholder: before class
        } else {
            due = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day // end of the due day
        }

        // Remove every date phrase (and empty "Week 14 ()" labels) from the title.
        var titleSource = line
        for range in allDatePhraseRanges(in: line).reversed() {
            titleSource = (titleSource as NSString).replacingCharacters(in: range, with: " ")
        }
        let title = cleanTitle(titleSource, kind: kind)
        return CourseDeadline(course: course, title: title, kind: kind, due: due, hasTime: mentionsTime)
    }

    static func cleanTitle(_ raw: String, kind: DeadlineKind) -> String {
        var t = raw
        let junk = [
            #"(?i)\bweek\s*\d+\b"#, #"(?i)\bdue\b(\s+(on|by|at))?"#, #"(?i)\b(on|by|at)\s*$"#,
            #"(?i)\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, #"^[\s•\-–—:|*\d.)(]+"#, #"[\s\-–—:|*,(]+$"#, #"\(\s*\)"#
        ]
        for pattern in junk {
            t = t.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:|,.;()"))
        if t.isEmpty { return kind.displayName }
        if t.count > 60 { t = String(t.prefix(57)) + "…" }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// "MWF 10:00-10:50", "TTh 2:00–3:15 PM", "Mon/Wed 9:30-10:45am", "Tuesdays and Thursdays 1-2:15pm".
    static func classMeeting(in line: String, course: String) -> ClassMeeting? {
        let lower = line.lowercased()
        guard lower.range(of: #"\b(lecture|class|meets|meeting|section|time|when|schedule)\b"#, options: .regularExpression) != nil
                || lower.range(of: #"^\s*(mwf|tth|tr|mw)\b"#, options: .regularExpression) != nil else { return nil }
        guard let days = weekdays(in: lower), !days.isEmpty,
              let (start, end) = timeRange(in: lower) else { return nil }
        return ClassMeeting(course: course, weekdays: days, startMinutes: start, endMinutes: end)
    }

    private static func weekdays(in l: String) -> Set<Int>? {
        // Compact codes first.
        let codes: [(String, Set<Int>)] = [
            (#"\bmwf\b"#, [2, 4, 6]), (#"\b(tth|tuth|tr|t/th|tu/th)\b"#, [3, 5]),
            (#"\bmw\b"#, [2, 4]), (#"\bwf\b"#, [4, 6])
        ]
        for (pattern, days) in codes where l.range(of: pattern, options: .regularExpression) != nil { return days }

        let names: [(String, Int)] = [
            ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7), ("sun", 1)
        ]
        var found = Set<Int>()
        for (prefix, day) in names where l.range(of: "\\b\(prefix)[a-z]*\\b", options: .regularExpression) != nil {
            found.insert(day)
        }
        return found.isEmpty ? nil : found
    }

    private static func timeRange(in l: String) -> (Int, Int)? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|–|—|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) else { return nil }
        let ns = l as NSString
        func int(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
        func str(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        guard let sh = int(1), let eh = int(4), (1...12).contains(sh) || (0...23).contains(sh) else { return nil }
        let endMeridiem = str(6)
        let startMeridiem = str(3) ?? endMeridiem

        func to24(_ h: Int, _ meridiem: String?) -> Int {
            switch meridiem {
            case "am": return h == 12 ? 0 : h
            case "pm": return h == 12 ? 12 : h + 12
            default: return (1...7).contains(h) ? h + 12 : h   // classes at "2:00" mean 2 PM
            }
        }
        var start = to24(sh, startMeridiem) * 60 + (int(2) ?? 0)
        var end = to24(eh, endMeridiem) * 60 + (int(5) ?? 0)
        // "11-12:15pm": start shares the end's meridiem only if that keeps it before the end.
        if start >= end, startMeridiem == endMeridiem, str(3) == nil { start = to24(sh, "am") * 60 + (int(2) ?? 0) }
        if end <= start { end += 12 * 60 }
        guard end > start, end - start <= 6 * 60 else { return nil }
        return (start, end)
    }
}
