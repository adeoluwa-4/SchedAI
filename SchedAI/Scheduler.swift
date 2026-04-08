import Foundation

struct Scheduler {
    static func planToday(
        tasks: inout [TaskItem],
        workStart: Date,
        workEnd: Date,
        day: Date = Date(),
        bufferMinutes: Int = 6
    ) -> Int {

        let cal = Calendar.current

        func combine(_ time: Date) -> Date {
            let dayComps = cal.dateComponents([.year, .month, .day], from: day)
            let t = cal.dateComponents([.hour, .minute, .second], from: time)
            var merged = DateComponents()
            merged.year = dayComps.year
            merged.month = dayComps.month
            merged.day = dayComps.day
            merged.hour = t.hour
            merged.minute = t.minute
            merged.second = t.second
            return cal.date(from: merged) ?? day
        }

        let startOfWindow = combine(workStart)
        let endOfWindow   = combine(workEnd)

        // Keep pinned tasks. Clear any previously auto-scheduled tasks so re-planning can reshuffle.
        for i in tasks.indices {
            guard !tasks[i].isCompleted else { continue }
            if tasks[i].isPinned {
                if let s = tasks[i].scheduledStart, tasks[i].scheduledEnd == nil {
                    tasks[i].scheduledEnd = s.addingTimeInterval(TimeInterval(max(5, tasks[i].estimatedMinutes) * 60))
                }
            } else {
                tasks[i].scheduledStart = nil
                tasks[i].scheduledEnd = nil
            }
        }

        var pinned: [(id: UUID, start: Date, end: Date)] = []
        var flexible: [TaskItem] = []

        for t in tasks where !t.isCompleted {
            if t.isPinned, let s = t.scheduledStart {
                let e = t.scheduledEnd ?? s.addingTimeInterval(TimeInterval(max(5, t.estimatedMinutes) * 60))
                pinned.append((t.id, s, e))
            } else {
                flexible.append(t)
            }
        }

        pinned.sort { $0.start < $1.start }

        var busy: [(start: Date, end: Date)] = []
        for p in pinned {
            let s = max(p.start, startOfWindow)
            let e = min(p.end, endOfWindow)
            if s < e { busy.append((s, e)) }
        }
        busy.sort { $0.start < $1.start }

        func addBusy(_ interval: (start: Date, end: Date)) {
            busy.append(interval)
            busy.sort { $0.start < $1.start }
        }

        func findSlot(startingAt candidateStart: Date, durationMinutes: Int) -> Date? {
            var candidate = max(candidateStart, startOfWindow)
            let duration = TimeInterval(max(5, durationMinutes) * 60)

            while true {
                let end = candidate.addingTimeInterval(duration)
                if end > endOfWindow { return nil }

                if let block = busy.first(where: { $0.start < end && $0.end > candidate }) {
                    candidate = block.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
                    continue
                }

                addBusy((start: candidate, end: end))
                return candidate
            }
        }

        flexible.sort { a, b in
            if a.priority != b.priority {
                return a.priority.sortRank < b.priority.sortRank
            }
            return a.estimatedMinutes > b.estimatedMinutes
        }

        var overflow = 0
        for t in flexible {
            guard let slotStart = findSlot(startingAt: startOfWindow, durationMinutes: t.estimatedMinutes) else {
                overflow += 1
                continue
            }
            let slotEnd = slotStart.addingTimeInterval(TimeInterval(max(5, t.estimatedMinutes) * 60))
            if let idx = tasks.firstIndex(where: { $0.id == t.id }) {
                tasks[idx].scheduledStart = slotStart
                tasks[idx].scheduledEnd = slotEnd
            }
        }

        return overflow
    }
}
