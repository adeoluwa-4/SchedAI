import Foundation

struct Scheduler {
    static func planToday(
        tasks: inout [TaskItem],
        workStart: Date,
        workEnd: Date,
        day: Date = Date(),
        now: Date = Date(),
        bufferMinutes: Int = 6,
        externalBusyIntervals: [DateInterval] = []
    ) -> Int {

        let cal = Calendar.current
        let planningDay = cal.startOfDay(for: day)

        func taskDay(_ task: TaskItem) -> Date? {
            if let target = task.targetDay {
                return cal.startOfDay(for: target)
            }
            if task.isPinned, let start = task.scheduledStart {
                return cal.startOfDay(for: start)
            }
            return nil
        }

        func appliesToPlanningDay(_ task: TaskItem) -> Bool {
            guard let d = taskDay(task) else { return true }
            return cal.isDate(d, inSameDayAs: planningDay)
        }

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

        let rawStartOfWindow = combine(workStart)
        let endOfWindow   = combine(workEnd)
        let todayStart = cal.startOfDay(for: now)
        let futureStart = now.addingTimeInterval(TimeInterval(max(10, bufferMinutes) * 60))
        let startOfWindow = cal.isDate(planningDay, inSameDayAs: todayStart)
            ? max(rawStartOfWindow, futureStart)
            : rawStartOfWindow

        // Keep pinned tasks. Clear any previously auto-scheduled tasks so re-planning can reshuffle.
        for i in tasks.indices {
            guard !tasks[i].isCompleted else { continue }
            guard appliesToPlanningDay(tasks[i]) else { continue }
            if tasks[i].isPinned {
                if let s = tasks[i].scheduledStart {
                    tasks[i].targetDay = cal.startOfDay(for: s)
                    if tasks[i].scheduledEnd == nil {
                        tasks[i].scheduledEnd = s.addingTimeInterval(TimeInterval(max(5, tasks[i].estimatedMinutes) * 60))
                    }
                }
            } else {
                tasks[i].scheduledStart = nil
                tasks[i].scheduledEnd = nil
            }
        }

        var pinned: [(id: UUID, start: Date, end: Date)] = []
        var flexible: [TaskItem] = []

        for t in tasks where !t.isCompleted && appliesToPlanningDay(t) {
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

        for interval in externalBusyIntervals {
            let s = max(interval.start, startOfWindow)
            let e = min(interval.end, endOfWindow)
            if s < e { busy.append((s, e)) }
        }

        func normalizeBusy(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
            let sorted = intervals.sorted { $0.start < $1.start }
            guard !sorted.isEmpty else { return [] }

            var merged: [(start: Date, end: Date)] = [sorted[0]]
            for interval in sorted.dropFirst() {
                let last = merged[merged.count - 1]
                if interval.start <= last.end {
                    merged[merged.count - 1] = (start: last.start, end: max(last.end, interval.end))
                } else {
                    merged.append(interval)
                }
            }
            return merged
        }

        busy = normalizeBusy(busy)

        func addBusy(_ interval: (start: Date, end: Date)) {
            busy.append(interval)
            busy = normalizeBusy(busy)
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
                tasks[idx].targetDay = planningDay
            }
        }

        return overflow
    }
}
