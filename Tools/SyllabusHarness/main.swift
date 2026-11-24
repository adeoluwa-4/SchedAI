import Foundation
import PDFKit
import Vision
import AppKit

// Syllabus harness: run the real SyllabusReader over a folder of syllabi.
// Usage: ./run.sh [folder]   (default: ./syllabi)
//
// Accepts .pdf, .txt, .md, .png, .jpg. For each file prints what was found,
// plus "unmatched" lines (they contain a date but produced no deadline), which
// is where misses hide. Optional answer key next to a file: NAME.expected.txt
// with lines like `2026-12-04 exam` (kinds: final exam quiz paper project
// assignment lab reading other). Gives precision/recall per file and overall.

let folder = CommandLine.arguments.dropFirst().first ?? "syllabi"
let fm = FileManager.default
let exts: Set<String> = ["pdf", "txt", "md", "png", "jpg", "jpeg"]
let files = ((try? fm.contentsOfDirectory(atPath: folder)) ?? [])
    .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) && !$0.contains(".expected.") }
    .sorted()
if files.isEmpty { print("No syllabi in \(folder). Drop PDFs, photos or .txt files there."); exit(0) }

func ocr(_ path: String) -> String {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

func extract(_ path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "pdf": return (try? SyllabusReader.text(fromPDF: URL(fileURLWithPath: path))) ?? ""
    case "png", "jpg", "jpeg": return ocr(path)
    default: return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}

let cal = Calendar.current
let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
let dfT = DateFormatter(); dfT.dateFormat = "yyyy-MM-dd HH:mm"
var totalFound = 0, totalExpected = 0, totalHit = 0, totalFiles = 0, totalEmpty = 0

for name in files {
    let path = "\(folder)/\(name)"
    let text = extract(path)
    totalFiles += 1
    print("\n━━━ \(name) ━━━")
    if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
        print("⚠️  No readable text (scanned PDF? try a photo/OCR or paste the text)")
        totalEmpty += 1; continue
    }
    let r = SyllabusReader.read(text)
    print("Course: \(r.course ?? "— not found —")")
    for c in r.classes { print("Class:  \(c.weekdaySummary) \(c.timeSummary)") }
    if r.classes.isEmpty { print("Class:  — none found —") }
    print("Deadlines (\(r.deadlines.count)):")
    for d in r.deadlines {
        print("  \(d.hasTime ? dfT.string(from: d.due) : df.string(from: d.due))  \(d.kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(d.title)")
    }
    totalFound += r.deadlines.count

    // Lines with a date-looking phrase that produced no deadline: likely misses.
    let used = Set(r.deadlines.map { $0.title.lowercased() })
    let missed = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
        guard line.count > 6, SyllabusReader.datePhraseRange(in: line) != nil else { return false }
        let l = line.lowercased()
        return !used.contains { !$0.isEmpty && l.contains($0) }
    }
    if !missed.isEmpty {
        print("Unmatched lines with dates (check for misses):")
        for l in missed.prefix(15) { print("  ? \(l.prefix(100))") }
    }

    let keyPath = (path as NSString).deletingPathExtension + ".expected.txt"
    if let key = try? String(contentsOfFile: keyPath, encoding: .utf8) {
        let expected = key.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let found = Set(r.deadlines.map { "\(df.string(from: $0.due)) \($0.kind.rawValue)" })
        let want = Set(expected)
        let hit = found.intersection(want)
        totalExpected += want.count; totalHit += hit.count
        print("Score: \(hit.count)/\(want.count) expected found; \(found.subtracting(want).count) extra")
        for m in want.subtracting(found).sorted() { print("  MISSED: \(m)") }
        for x in found.subtracting(want).sorted() { print("  EXTRA:  \(x)") }
    }
}

print("\n═══ Summary ═══")
print("\(totalFiles) files, \(totalEmpty) unreadable, \(totalFound) deadlines found")
if totalExpected > 0 {
    print(String(format: "Recall vs answer keys: %d/%d = %.0f%%", totalHit, totalExpected, 100 * Double(totalHit) / Double(totalExpected)))
}
