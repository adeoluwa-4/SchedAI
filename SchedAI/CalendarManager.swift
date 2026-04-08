import Foundation
import Combine
#if canImport(EventKit)
import EventKit
#endif

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var isAuthorized: Bool = false

    /// Non-prompting calendar connection state.
    enum ConnectionStatus: Equatable {
        case notConnected      // notDetermined
        case connected         // full access / authorized
        case denied            // denied / restricted / writeOnly
        case unavailable       // EventKit not available
    }

    /// Result of a sync attempt.
    enum SyncResult: Equatable {
        case success(Int)
        case notConnected
        case denied
        case unavailable
        case failed(String)
    }

    #if canImport(EventKit)
    private let store = EKEventStore()
    #endif

    private init() {
        self.isAuthorized = (connectionStatus() == .connected)
    }

    // MARK: - Authorization (NON-prompting status)

    func connectionStatus() -> ConnectionStatus {
        #if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(iOS 17.0, *) {
            switch status {
            case .fullAccess:
                isAuthorized = true
                return .connected
            case .authorized:
                // Back-compat on some SDKs
                isAuthorized = true
                return .connected
            case .writeOnly:
                // Treat write-only as denied because we can't read to avoid duplicates.
                isAuthorized = false
                return .denied
            case .notDetermined:
                isAuthorized = false
                return .notConnected
            case .denied, .restricted:
                isAuthorized = false
                return .denied
            @unknown default:
                isAuthorized = false
                return .denied
            }
        } else {
            switch status {
            case .authorized:
                isAuthorized = true
                return .connected
            case .notDetermined:
                isAuthorized = false
                return .notConnected
            case .denied, .restricted:
                isAuthorized = false
                return .denied
            @unknown default:
                isAuthorized = false
                return .denied
            }
        }
        #else
        isAuthorized = false
        return .unavailable
        #endif
    }

    /// Request permission ONLY from an explicit user action (e.g., tapping "Connect Calendar").
    func requestAccess(completion: @escaping (Bool) -> Void) {
        #if canImport(EventKit)
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.isAuthorized = granted
                    completion(granted)
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.isAuthorized = granted
                    completion(granted)
                }
            }
        }
        #else
        isAuthorized = false
        completion(false)
        #endif
    }

    /// Request access (user-driven) and ensure the SchedAI calendar exists.
    func requestAccessAndEnsureCalendar(completion: @escaping (ConnectionStatus, String?) -> Void) {
        #if canImport(EventKit)
        requestAccess { [weak self] granted in
            guard let self else { return }
            if !granted {
                completion(.denied, "Calendar access was denied. Enable it in iOS Settings → Privacy & Security → Calendars.")
                return
            }

            if self.ensureCalendar() != nil {
                completion(.connected, nil)
            } else {
                completion(.notConnected, "Could not create/find the SchedAI calendar.")
            }
        }
        #else
        completion(.unavailable, "Calendar is unavailable on this device.")
        #endif
    }

    // MARK: - Public sync API

    /// Sync today's scheduled tasks into a dedicated "SchedAI" calendar.
    /// Never prompts for permission; returns a status instead.
    func upsertTodayEvents(from tasks: [TaskItem], day: Date = Date()) -> SyncResult {
        #if canImport(EventKit)
        switch connectionStatus() {
        case .connected:
            break
        case .notConnected:
            return .notConnected
        case .denied:
            return .denied //0.23  0.21 ,4.86   0.15, 6.61
        case .unavailable:
            return .unavailable
        }

        guard let calendar = ensureCalendar() else {
            return .failed("Could not create/find SchedAI calendar")
        }

        let (start, end) = dayBounds(day)
        let scheduled = tasks
            .filter { !$0.isCompleted }
            .filter { t in
                guard let s = t.scheduledStart else { return false }
                return Calendar.current.isDate(s, inSameDayAs: day)
            }

        // Fetch existing events in our calendar for the day
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let existing = store.events(matching: predicate)

        var map = loadEventMap()
        let wantedIDs = Set(scheduled.map { $0.id.uuidString })

        var failure: String? = nil

        // Delete events that no longer correspond to scheduled tasks for this day
        for ev in existing {
            if let uid = extractTaskID(from: ev), !wantedIDs.contains(uid) {
                do {
                    try store.remove(ev, span: .thisEvent, commit: false)
                    if let (taskID, _) = map.first(where: { $0.value == ev.eventIdentifier }) {
                        map.removeValue(forKey: taskID)
                    }
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }
        }

        if failure == nil {
            // Upsert events for each scheduled task
            for t in scheduled {
                guard let s = t.scheduledStart else { continue }
                let e = t.scheduledEnd ?? s.addingTimeInterval(TimeInterval(max(5, t.estimatedMinutes) * 60))

                if let existingEvent = fetchEvent(for: t.id, from: existing, map: map) {
                    var needsSave = false
                    if existingEvent.startDate != s || existingEvent.endDate != e {
                        existingEvent.startDate = s
                        existingEvent.endDate = e
                        needsSave = true
                    }
                    if existingEvent.title != t.title {
                        existingEvent.title = t.title
                        needsSave = true
                    }
                    if needsSave {
                        do {
                            try store.save(existingEvent, span: .thisEvent, commit: false)
                        } catch {
                            failure = error.localizedDescription
                            break
                        }
                    }
                } else {
                    let ev = EKEvent(eventStore: store)
                    ev.calendar = calendar
                    ev.title = t.title
                    ev.startDate = s
                    ev.endDate = e
                    ev.notes = "SchedAI_ID:\(t.id.uuidString)"
                    do {
                        try store.save(ev, span: .thisEvent, commit: false)
                        map[t.id.uuidString] = ev.eventIdentifier
                    } catch {
                        failure = error.localizedDescription
                        break
                    }
                }
            }
        }

        if let failure {
            return .failed(failure)
        }

        do {
            try store.commit()
        } catch {
            return .failed(error.localizedDescription)
        }

        saveEventMap(map)
        return .success(scheduled.count)
        #else
        return .unavailable
        #endif
    }

    /// Delete a single task's event (best-effort). Does not prompt.
    func deleteEvent(for taskID: UUID) {
        #if canImport(EventKit)
        guard connectionStatus() == .connected else { return }
        guard let calendar = ensureCalendar() else { return }

        var map = loadEventMap()

        // 1) Try mapping first (fast path)
        if let eventID = map[taskID.uuidString], let ev = store.event(withIdentifier: eventID) {
            do {
                try store.remove(ev, span: .thisEvent, commit: true)
                map.removeValue(forKey: taskID.uuidString)
                saveEventMap(map)
            } catch { }
            return
        }

        // 2) Fallback: search around today
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(2 * 86400)

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let events = store.events(matching: predicate)

        if let ev = events.first(where: { extractTaskID(from: $0) == taskID.uuidString }) {
            do {
                try store.remove(ev, span: .thisEvent, commit: true)
                map.removeValue(forKey: taskID.uuidString)
                saveEventMap(map)
            } catch { }
        }
        #endif
    }

    // MARK: - Helpers
    #if canImport(EventKit)

    private func ensureCalendar() -> EKCalendar? {
        let idKey = "SchedAI_CalendarIdentifier"
        if let saved = UserDefaults.standard.string(forKey: idKey), let cal = store.calendar(withIdentifier: saved) {
            return cal
        }

        if let cal = store.calendars(for: .event).first(where: { $0.title == "SchedAI" }) {
            UserDefaults.standard.set(cal.calendarIdentifier, forKey: idKey)
            return cal
        }

        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "SchedAI"
        cal.source = preferredSource()
        do {
            try store.saveCalendar(cal, commit: true)
            UserDefaults.standard.set(cal.calendarIdentifier, forKey: idKey)
            return cal
        } catch {
            return nil
        }
    }

    private func preferredSource() -> EKSource? {
        let sources = store.sources
        if let icloud = sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            return icloud
        }
        return sources.first(where: { $0.sourceType == .local })
    }

    private func dayBounds(_ day: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    private func extractTaskID(from event: EKEvent) -> String? {
        if let notes = event.notes,
           let range = notes.range(of: "SchedAI_ID:") {
            let idStart = notes.index(range.upperBound, offsetBy: 0)
            let id = String(notes[idStart...])
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Back-compat tag
        if let notes = event.notes,
           let range = notes.range(of: "SchedAI Task ") {
            let idStart = notes.index(range.upperBound, offsetBy: 0)
            let id = String(notes[idStart...])
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func fetchEvent(for taskID: UUID, from events: [EKEvent], map: [String: String]) -> EKEvent? {
        if let mapped = map[taskID.uuidString] {
            return events.first(where: { $0.eventIdentifier == mapped })
        }
        return events.first(where: { extractTaskID(from: $0) == taskID.uuidString })
    }

    private func loadEventMap() -> [String: String] {
        let key = "SchedAI_EventMap"
        if let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] { return dict }
        return [:]
    }

    private func saveEventMap(_ map: [String: String]) {
        let key = "SchedAI_EventMap"
        UserDefaults.standard.set(map, forKey: key)
    }

    #endif
}
