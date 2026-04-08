import Foundation
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
final class AppState: ObservableObject {

    private var midnightTimer: Timer? = nil

    private enum DefaultsKey {
        static let remindersEnabled = "remindersEnabled"
        static let reminderLeadMinutes = "reminderLeadMinutes"
        static let theme = "appThemePreference"
        static let lastResetDay = "lastResetDay"
        static let calendarSyncEnabled = "calendarSyncEnabled"
        static let userDisplayName = "userDisplayName"
    }

    @Published var tasks: [TaskItem] = [] {
        didSet { persist() }
    }

    @Published var lastPlanOverflow: Int = 0

    /// User-facing calendar sync feedback (used to avoid silent failures).
    @Published var calendarSyncMessage: String? = nil
    /// Toast feedback for successful calendar connect.
    @Published var calendarSyncToast: String? = nil

    /// Current calendar connection state (non-prompting).
    @Published var calendarConnectionStatus: CalendarManager.ConnectionStatus = .notConnected

    /// Date currently being planned/viewed in Today screen.
    @Published var planningDate: Date = Calendar.current.startOfDay(for: Date()) {
        didSet {
            let normalized = Calendar.current.startOfDay(for: planningDate)
            if normalized != planningDate { planningDate = normalized }
        }
    }

    @Published var workStart: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())! {
        didSet { validateWorkWindow() }
    }

    @Published var workEnd: Date = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())! {
        didSet { validateWorkWindow() }
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: DefaultsKey.theme)
        }
    }

    /// Whether to schedule local notifications before planned tasks.
    @Published var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: DefaultsKey.remindersEnabled)

            if remindersEnabled {
                enableRemindersUserDriven()
            } else {
                NotificationManager.clearAll(delivered: true, pending: true)
            }
        }
    }

    /// How many minutes before a task start we should notify.
    @Published var reminderLeadMinutes: Int {
        didSet {
            if reminderLeadMinutes < 1 {
                reminderLeadMinutes = 1
                return
            }

            UserDefaults.standard.set(reminderLeadMinutes, forKey: DefaultsKey.reminderLeadMinutes)

            guard remindersEnabled else { return }
            rescheduleReminders()
        }
    }

    /// Whether to sync scheduled tasks into Apple Calendar.
    @Published var calendarSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(calendarSyncEnabled, forKey: DefaultsKey.calendarSyncEnabled)
        }
    }

    /// User's display name (persisted when available, e.g., from Sign in with Apple).
    @Published var userDisplayName: String? {
        didSet {
            let trimmed = userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = trimmed, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: DefaultsKey.userDisplayName)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.userDisplayName)
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard

        let themeRaw = defaults.string(forKey: DefaultsKey.theme) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: themeRaw) ?? .system

        // Default OFF for first-run so we don't prompt on launch.
        self.remindersEnabled = (defaults.object(forKey: DefaultsKey.remindersEnabled) as? Bool) ?? false
        self.reminderLeadMinutes = (defaults.object(forKey: DefaultsKey.reminderLeadMinutes) as? Int) ?? 5
        self.calendarSyncEnabled = (defaults.object(forKey: DefaultsKey.calendarSyncEnabled) as? Bool) ?? false
        self.userDisplayName = defaults.string(forKey: DefaultsKey.userDisplayName)

        _ = restore()

        // Permissions are intentionally not requested on launch.
        hydratePermissionDependentFeatures()
        refreshCalendarConnectionStatus()

        // Daily rollover: reset schedules at midnight and when returning after midnight
        performDailyRolloverIfNeeded(now: Date())
        scheduleMidnightReset()

        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    // MARK: - Work Window Validation

    private func validateWorkWindow() {
        let cal = Calendar.current
        let startComps = cal.dateComponents([.hour, .minute], from: workStart)
        let endComps = cal.dateComponents([.hour, .minute], from: workEnd)

        let startMinutes = (startComps.hour ?? 0) * 60 + (startComps.minute ?? 0)
        let endMinutes = (endComps.hour ?? 0) * 60 + (endComps.minute ?? 0)

        if endMinutes <= startMinutes {
            let adjustedMinutes = startMinutes + 60
            let newHour = adjustedMinutes / 60
            let newMinute = adjustedMinutes % 60

            if let adjusted = cal.date(bySettingHour: newHour, minute: newMinute, second: 0, of: Date()) {
                workEnd = adjusted
            }
        }
    }

    // MARK: - Permissions / feature hydration

    private func hydratePermissionDependentFeatures() {
        // Notifications
        if remindersEnabled {
            NotificationManager.authorizationStatus { [weak self] (status: NotificationManager.AuthorizationState) in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.rescheduleRemindersWithoutPrompt()
                case .denied, .notDetermined:
                    Task { @MainActor in self.remindersEnabled = false }
                }
            }
        }

        // Calendar
        if calendarSyncEnabled {
            refreshCalendarConnectionStatus()
        }
    }

    func refreshCalendarConnectionStatus() {
        calendarConnectionStatus = CalendarManager.shared.connectionStatus()
    }

    /// User-driven calendar sync enablement. Requests permission if needed and creates/links the SchedAI calendar.
    func enableCalendarSyncUserDriven() {
        let status = CalendarManager.shared.connectionStatus()
        calendarConnectionStatus = status

        switch status {
        case .connected:
            calendarSyncEnabled = true

        case .denied:
            calendarSyncEnabled = false
            calendarSyncMessage = "Calendar access is denied. Enable it in iOS Settings → Privacy & Security → Calendars."

        case .unavailable:
            calendarSyncEnabled = false
            calendarSyncMessage = "Calendar is unavailable on this device."

        case .notConnected:
            calendarSyncEnabled = true
            CalendarManager.shared.requestAccessAndEnsureCalendar { [weak self] status, message in
                guard let self else { return }
                self.calendarConnectionStatus = status
                switch status {
                case .connected:
                    self.calendarSyncEnabled = true
                    self.calendarSyncToast = "Calendar connected"
                case .denied, .unavailable, .notConnected:
                    self.calendarSyncEnabled = false
                    if let message { self.calendarSyncMessage = message }
                }
            }
        }
    }

    private func enableRemindersUserDriven() {
        let tasksSnapshot = tasks
            .filter { !$0.isCompleted }
            .filter { $0.scheduledStart != nil }

        let lead = reminderLeadMinutes

        NotificationManager.authorizationStatus { [weak self] (status: NotificationManager.AuthorizationState) in
            guard let self else { return }

            switch status {
            case .authorized:
                NotificationManager.clearAll(delivered: true, pending: true)
                NotificationManager.scheduleReminders(for: tasksSnapshot, minutesBefore: lead)

            case .notDetermined:
                NotificationManager.requestPermission { granted in
                    guard granted else {
                        Task { @MainActor in self.remindersEnabled = false }
                        return
                    }
                    NotificationManager.clearAll(delivered: true, pending: true)
                    NotificationManager.scheduleReminders(for: tasksSnapshot, minutesBefore: lead)
                }

            case .denied:
                Task { @MainActor in self.remindersEnabled = false }
            }
        }
    }

    deinit {
        midnightTimer?.invalidate()
        midnightTimer = nil
        #if os(iOS)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    // MARK: - CRUD

    func addTask(_ t: TaskItem) {
        tasks.insert(t, at: 0)
        if remindersEnabled { rescheduleReminders() }
    }

    func addTask(title: String, estimatedMinutes: Int = 30, priority: TaskPriority = .medium) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addTask(TaskItem(title: trimmed, estimatedMinutes: estimatedMinutes, priority: priority))
    }

    func updateTask(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        tasks[i] = t
        if remindersEnabled { rescheduleReminders() }
    }

    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        NotificationManager.cancelReminder(for: id)
        if calendarSyncEnabled {
            CalendarManager.shared.deleteEvent(for: id)
        }
    }

    func toggleComplete(id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isCompleted.toggle()
        if remindersEnabled { rescheduleReminders() }
    }

    // MARK: - Planning

    func setPlanningDate(_ day: Date) {
        planningDate = Calendar.current.startOfDay(for: day)
    }

    func planToday(for day: Date = Date()) {
        planningDate = Calendar.current.startOfDay(for: day)
        lastPlanOverflow = Scheduler.planToday(
            tasks: &tasks,
            workStart: workStart,
            workEnd: workEnd,
            day: day
        )

        if remindersEnabled {
            rescheduleReminders()
        }

        calendarSyncIfEnabled(day: day, showSuccessMessage: false)
    }

    // MARK: - Multi-day Planning

    func planDays(start: Date, count: Int) {
        guard count > 0 else { return }

        let cal = Calendar.current
        var totalOverflow = 0

        for dayOffset in 0..<count {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: start)) else { continue }

            let overflow = Scheduler.planToday(
                tasks: &tasks,
                workStart: workStart,
                workEnd: workEnd,
                day: day
            )
            totalOverflow += overflow
        }

        lastPlanOverflow = totalOverflow

        if remindersEnabled {
            rescheduleReminders()
        }

        calendarSyncIfEnabled(day: start, showSuccessMessage: false)
    }

    func planMonth(containing date: Date) {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: date) else { return }

        let comps = cal.dateComponents([.year, .month], from: date)
        guard let monthStart = cal.date(from: comps) else { return }

        planDays(start: monthStart, count: range.count)
    }

    func planNextMonth(from date: Date) {
        let cal = Calendar.current
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: cal.startOfDay(for: date)) else { return }
        planMonth(containing: nextMonth)
    }

    func syncTodayToCalendar(day: Date = Date()) {
        calendarSyncIfEnabled(day: day, showSuccessMessage: true)
    }

    private func calendarSyncIfEnabled(day: Date, showSuccessMessage: Bool) {
        guard calendarSyncEnabled else { return }

        let result = CalendarManager.shared.upsertTodayEvents(from: tasks, day: day)
        refreshCalendarConnectionStatus()

        switch result {
        case .success(let syncedCount):
            if showSuccessMessage {
                calendarSyncMessage = "Synced \(syncedCount) task\(syncedCount == 1 ? "" : "s") to your SchedAI calendar."
            }
        case .notConnected:
            calendarSyncMessage = "Calendar is not connected. Go to Settings → Calendar → Connect Calendar."
        case .denied:
            calendarSyncMessage = "Calendar access is denied. Enable it in iOS Settings → Privacy & Security → Calendars."
        case .unavailable:
            calendarSyncMessage = "Calendar is unavailable on this device."
        case .failed(let reason):
            calendarSyncMessage = "Calendar sync failed: \(reason)"
        }
    }

    private func rescheduleReminders() {
        let tasksSnapshot = tasks
            .filter { !$0.isCompleted }
            .filter { $0.scheduledStart != nil }

        let lead = reminderLeadMinutes

        NotificationManager.authorizationStatus { (status: NotificationManager.AuthorizationState) in
            guard status == .authorized else { return }
            NotificationManager.clearAll(delivered: true, pending: true)
            NotificationManager.scheduleReminders(for: tasksSnapshot, minutesBefore: lead)
        }
    }

    private func rescheduleRemindersWithoutPrompt() {
        guard remindersEnabled else { return }
        let tasksSnapshot = tasks
            .filter { !$0.isCompleted }
            .filter { $0.scheduledStart != nil }

        NotificationManager.authorizationStatus { (status: NotificationManager.AuthorizationState) in
            guard status == .authorized else { return }
            NotificationManager.clearAll(delivered: true, pending: true)
            NotificationManager.scheduleReminders(for: tasksSnapshot, minutesBefore: self.reminderLeadMinutes)
        }
    }

    // MARK: - Persistence

    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("tasks.json")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: saveURL, options: [.atomic])
    }

    @discardableResult
    private func restore() -> Bool {
        guard let data = try? Data(contentsOf: saveURL) else { return false }
        guard let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else { return false }
        tasks = decoded
        return true
    }

    // MARK: - Daily rollover (reset at midnight)

    @objc private func appWillEnterForeground() {
        performDailyRolloverIfNeeded(now: Date())
        scheduleMidnightReset()
    }

    private func scheduleMidnightReset() {
        midnightTimer?.invalidate()
        midnightTimer = nil

        let now = Date()
        let cal = Calendar.current
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let interval = max(1, startOfTomorrow.timeIntervalSince(now))

        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performDailyRolloverIfNeeded(now: Date())
                self?.scheduleMidnightReset()
            }
        }
    }

    /// NEW behavior:
    /// - Clear schedule times from tasks scheduled before today (replanning stays clean)
    /// - Remove tasks that were created yesterday AND were scheduled yesterday (so "today" starts fresh)
    private func performDailyRolloverIfNeeded(now: Date) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)

        // Already reset today?
        if let last = loadLastResetDay(), cal.isDate(last, inSameDayAs: todayStart) {
            return
        }

        // Define “yesterday” as the last reset day (best signal),
        // otherwise just the calendar day before today.
        let lastActiveDayStart =
            loadLastResetDay()
            ?? (cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart)

        var changed = false
        var newTasks: [TaskItem] = []
        newTasks.reserveCapacity(tasks.count)

        for var t in tasks {
            // Capture original schedule BEFORE we potentially clear it
            let originalStart = t.scheduledStart

            let wasCreatedYesterday = cal.isDate(t.createdAt, inSameDayAs: lastActiveDayStart)
            let wasScheduledYesterday = originalStart.map { cal.isDate($0, inSameDayAs: lastActiveDayStart) } ?? false

            // 1) Clear schedules that are in the past so planning starts clean
            if let s = originalStart, s < todayStart {
                t.scheduledStart = nil
                t.scheduledEnd = nil
                changed = true
            }

            // 2) Remove yesterday’s “today tasks” so they don’t carry over
            if wasCreatedYesterday && wasScheduledYesterday {
                changed = true

                NotificationManager.cancelReminder(for: t.id)
                if calendarSyncEnabled {
                    CalendarManager.shared.deleteEvent(for: t.id)
                }
                continue
            }

            newTasks.append(t)
        }

        // Fresh day
        if lastPlanOverflow != 0 {
            lastPlanOverflow = 0
            changed = true
        }

        if changed {
            tasks = newTasks
        }

        // Reminders: only reschedule if enabled (no prompts)
        if remindersEnabled {
            rescheduleReminders()
        }

        saveLastResetDay(todayStart)
    }

    private func loadLastResetDay() -> Date? {
        let defaults = UserDefaults.standard
        if let ts = defaults.object(forKey: DefaultsKey.lastResetDay) as? TimeInterval {
            return Date(timeIntervalSinceReferenceDate: ts)
        }
        return nil
    }

    private func saveLastResetDay(_ dayStart: Date) {
        let defaults = UserDefaults.standard
        defaults.set(dayStart.timeIntervalSinceReferenceDate, forKey: DefaultsKey.lastResetDay)
    }
}
