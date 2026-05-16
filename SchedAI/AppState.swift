import Foundation
import SwiftUI
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif
#if os(iOS)
import UIKit
#endif

enum AppNotifications {
    static let widgetVoicePlannerRequested = Notification.Name("widget_voice_planner_requested")
}

@MainActor
final class AppState: ObservableObject {

    private var midnightTimer: Timer? = nil
    private var completionCleanupTimer: Timer? = nil
    private let completedTaskRetention: TimeInterval = 24 * 60 * 60

    private enum DefaultsKey {
        static let remindersEnabled = "remindersEnabled"
        static let reminderLeadMinutes = "reminderLeadMinutes"
        static let theme = "appThemePreference"
        static let lastResetDay = "lastResetDay"
        static let calendarSyncEnabled = "calendarSyncEnabled"
        static let userDisplayName = "userDisplayName"
        static let workWindowEnabled = "workWindowEnabled"
        static let workStart = "workStart"
        static let workEnd = "workEnd"
        static let unfinishedTaskPolicy = "unfinishedTaskPolicy"
        static let hostedAIConsent = "hostedAIConsent"
    }

    private enum WidgetBridge {
        static let appGroupID = "group.me.SchedAI.shared"
        static let tasksKey = "widget_shared_tasks_v1"
        static let voiceRequestKey = "widget_voice_request_v1"
    }

    private struct WidgetSharedTask: Codable {
        let id: UUID
        let title: String
        let priorityRaw: String
        let estimatedMinutes: Int
        let isCompleted: Bool
        let targetDay: Date?
        let scheduledStart: Date?
        let scheduledEnd: Date?
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
        didSet {
            validateWorkWindow()
            UserDefaults.standard.set(workStart, forKey: DefaultsKey.workStart)
        }
    }

    @Published var workEnd: Date = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())! {
        didSet {
            validateWorkWindow()
            UserDefaults.standard.set(workEnd, forKey: DefaultsKey.workEnd)
        }
    }

    @Published var workWindowEnabled: Bool {
        didSet {
            UserDefaults.standard.set(workWindowEnabled, forKey: DefaultsKey.workWindowEnabled)
        }
    }

    @Published var unfinishedTaskPolicy: UnfinishedTaskPolicy {
        didSet {
            UserDefaults.standard.set(unfinishedTaskPolicy.rawValue, forKey: DefaultsKey.unfinishedTaskPolicy)
        }
    }

    @Published var hostedAIConsent: Bool {
        didSet {
            UserDefaults.standard.set(hostedAIConsent, forKey: DefaultsKey.hostedAIConsent)
        }
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
        self.workWindowEnabled = (defaults.object(forKey: DefaultsKey.workWindowEnabled) as? Bool) ?? true
        let unfinishedRaw = defaults.string(forKey: DefaultsKey.unfinishedTaskPolicy) ?? UnfinishedTaskPolicy.askMe.rawValue
        self.unfinishedTaskPolicy = UnfinishedTaskPolicy(rawValue: unfinishedRaw) ?? .askMe
        self.hostedAIConsent = (defaults.object(forKey: DefaultsKey.hostedAIConsent) as? Bool) ?? false
        self.workStart = (defaults.object(forKey: DefaultsKey.workStart) as? Date) ?? workStart
        self.workEnd = (defaults.object(forKey: DefaultsKey.workEnd) as? Date) ?? workEnd
        validateWorkWindow()

        _ = restore()
        pruneExpiredCompletedTasks(now: Date())
        scheduleCompletedTaskCleanup()
        persistWidgetData()

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

    func schedulingWindow(for day: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let baseDay = cal.startOfDay(for: day)

        func combine(_ time: Date) -> Date {
            let dayComps = cal.dateComponents([.year, .month, .day], from: baseDay)
            let timeComps = cal.dateComponents([.hour, .minute, .second], from: time)
            var merged = DateComponents()
            merged.year = dayComps.year
            merged.month = dayComps.month
            merged.day = dayComps.day
            merged.hour = timeComps.hour
            merged.minute = timeComps.minute
            merged.second = timeComps.second
            return cal.date(from: merged) ?? baseDay
        }

        guard workWindowEnabled else {
            let start = combine(cal.date(bySettingHour: 0, minute: 0, second: 0, of: baseDay) ?? baseDay)
            let end = combine(cal.date(bySettingHour: 23, minute: 59, second: 0, of: baseDay) ?? baseDay)
            return (start, end)
        }

        return (combine(workStart), combine(workEnd))
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
        completionCleanupTimer?.invalidate()
        completionCleanupTimer = nil
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
        var task = normalizedCompletionState(t)
        if let start = task.scheduledStart {
            task.targetDay = Calendar.current.startOfDay(for: start)
        }
        tasks.insert(task, at: 0)
        if remindersEnabled { rescheduleReminders() }
        scheduleCompletedTaskCleanup()
    }

    func addTask(title: String, estimatedMinutes: Int = 30, priority: TaskPriority = .medium) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addTask(TaskItem(title: trimmed, estimatedMinutes: estimatedMinutes, priority: priority))
    }

    func updateTask(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        var task = normalizedCompletionState(t)
        if let start = task.scheduledStart {
            task.targetDay = Calendar.current.startOfDay(for: start)
        } else if let target = task.targetDay {
            task.targetDay = Calendar.current.startOfDay(for: target)
        }
        tasks[i] = task
        if remindersEnabled { rescheduleReminders() }
        scheduleCompletedTaskCleanup()
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
        tasks[i].completedAt = tasks[i].isCompleted ? Date() : nil
        if remindersEnabled { rescheduleReminders() }
        scheduleCompletedTaskCleanup()
    }

    private func normalizedCompletionState(_ task: TaskItem) -> TaskItem {
        var normalized = task
        if normalized.isCompleted {
            normalized.completedAt = normalized.completedAt ?? Date()
        } else {
            normalized.completedAt = nil
        }
        return normalized
    }

    func rescheduleTaskForLater(id: UUID, from now: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let day = Calendar.current.startOfDay(for: now)
        tasks[i].isPinned = false
        tasks[i].targetDay = day
        tasks[i].scheduledStart = nil
        tasks[i].scheduledEnd = nil
        planUnscheduledOnly(for: day)
    }

    // MARK: - Planning

    func setPlanningDate(_ day: Date) {
        planningDate = Calendar.current.startOfDay(for: day)
    }

    func planToday(for day: Date = Date()) {
        let targetDay = Calendar.current.startOfDay(for: day)
        planningDate = targetDay
        lastPlanOverflow = planSchedule(for: targetDay)

        if remindersEnabled {
            rescheduleReminders()
        }

        calendarSyncIfEnabled(day: targetDay, showSuccessMessage: false)
    }

    /// Schedule only currently unscheduled tasks for the selected day.
    /// Existing scheduled tasks are treated as fixed anchors for this planning pass.
    func planUnscheduledOnly(for day: Date = Date()) {
        planningDate = Calendar.current.startOfDay(for: day)
        let externalBusy = CalendarManager.shared.busyIntervals(on: planningDate) ?? []
        let window = schedulingWindow(for: planningDate)

        var tempPinned: [UUID] = []
        for i in tasks.indices where !tasks[i].isCompleted {
            if !tasks[i].isPinned, tasks[i].scheduledStart != nil {
                tasks[i].isPinned = true
                tempPinned.append(tasks[i].id)
            }
        }

        lastPlanOverflow = Scheduler.planToday(
            tasks: &tasks,
            workStart: window.start,
            workEnd: window.end,
            day: planningDate,
            now: Date(),
            externalBusyIntervals: externalBusy
        )

        for id in tempPinned {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].isPinned = false
            }
        }

        if remindersEnabled {
            rescheduleReminders()
        }

        calendarSyncIfEnabled(day: planningDate, showSuccessMessage: false)
    }

    // MARK: - Multi-day Planning

    func planDays(start: Date, count: Int) {
        guard count > 0 else { return }

        let cal = Calendar.current
        var totalOverflow = 0
        var plannedDays: [Date] = []

        for dayOffset in 0..<count {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: start)) else { continue }
            plannedDays.append(day)
            totalOverflow += planSchedule(for: day)
        }

        lastPlanOverflow = totalOverflow

        if remindersEnabled {
            rescheduleReminders()
        }

        calendarSyncIfEnabled(days: plannedDays, showSuccessMessage: false)
    }

    func planSpecificDays(_ days: [Date], focusDay: Date? = nil) {
        let cal = Calendar.current
        let normalizedDays = Array(Set(days.map { cal.startOfDay(for: $0) })).sorted()
        guard !normalizedDays.isEmpty else { return }

        if let focusDay {
            planningDate = cal.startOfDay(for: focusDay)
        } else if let firstDay = normalizedDays.first {
            planningDate = firstDay
        }

        var totalOverflow = 0
        for day in normalizedDays {
            totalOverflow += planSchedule(for: day)
        }
        lastPlanOverflow = totalOverflow

        if remindersEnabled {
            rescheduleReminders()
        }

        calendarSyncIfEnabled(days: normalizedDays, showSuccessMessage: false)
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

    private func planSchedule(for day: Date) -> Int {
        let targetDay = Calendar.current.startOfDay(for: day)
        let externalBusy = CalendarManager.shared.busyIntervals(on: targetDay) ?? []
        let window = schedulingWindow(for: targetDay)
        return Scheduler.planToday(
            tasks: &tasks,
            workStart: window.start,
            workEnd: window.end,
            day: targetDay,
            now: Date(),
            externalBusyIntervals: externalBusy
        )
    }

    private func calendarSyncIfEnabled(days: [Date], showSuccessMessage: Bool) {
        let cal = Calendar.current
        let normalizedDays = Array(Set(days.map { cal.startOfDay(for: $0) })).sorted()
        guard !normalizedDays.isEmpty else { return }

        var totalSynced = 0
        for day in normalizedDays {
            let previousMessage = calendarSyncMessage
            calendarSyncIfEnabled(day: day, showSuccessMessage: false)
            if calendarSyncMessage != previousMessage {
                return
            }

            let count = tasks.filter { task in
                guard !task.isCompleted, let start = task.scheduledStart else { return false }
                return cal.isDate(start, inSameDayAs: day)
            }.count
            totalSynced += count
        }

        if showSuccessMessage {
            calendarSyncMessage = "Synced \(totalSynced) task\(totalSynced == 1 ? "" : "s") to your SchedAI calendar."
        }
    }

    private func calendarSyncIfEnabled(day: Date, showSuccessMessage: Bool) {
        guard calendarSyncEnabled else { return }

        let targetDay = Calendar.current.startOfDay(for: day)
        let result = CalendarManager.shared.upsertTodayEvents(from: tasks, day: targetDay)
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
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchedAI", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks.json")
    }

    private var legacySaveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tasks.json")
    }

    private var protectedWriteOptions: Data.WritingOptions {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        return options
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: saveURL, options: protectedWriteOptions)
        persistWidgetData()
    }

    @discardableResult
    private func restore() -> Bool {
        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decoded
            return true
        }

        guard let legacyData = try? Data(contentsOf: legacySaveURL),
              let legacyDecoded = try? JSONDecoder().decode([TaskItem].self, from: legacyData)
        else { return false }

        tasks = legacyDecoded
        persist()
        return true
    }

    // MARK: - Daily rollover (reset at midnight)

    @objc private func appWillEnterForeground() {
        pruneExpiredCompletedTasks(now: Date())
        performDailyRolloverIfNeeded(now: Date())
        scheduleMidnightReset()
        scheduleCompletedTaskCleanup()
    }

    private func scheduleMidnightReset() {
        midnightTimer?.invalidate()
        midnightTimer = nil

        let now = Date()
        let cal = Calendar.current
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let interval = max(1, startOfTomorrow.timeIntervalSince(now))

        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let appState = self else { return }
            Task { @MainActor in
                appState.performDailyRolloverIfNeeded(now: Date())
                appState.scheduleMidnightReset()
            }
        }
    }

    private func scheduleCompletedTaskCleanup() {
        completionCleanupTimer?.invalidate()
        completionCleanupTimer = nil

        let now = Date()
        let nextRemovalDate = tasks
            .filter(\.isCompleted)
            .map { task -> Date in
                let completedAt = task.completedAt ?? task.createdAt
                return completedAt.addingTimeInterval(completedTaskRetention)
            }
            .filter { $0 > now }
            .min()

        guard let nextRemovalDate else { return }
        let interval = max(1, nextRemovalDate.timeIntervalSince(now))

        completionCleanupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let appState = self else { return }
            Task { @MainActor in
                appState.pruneExpiredCompletedTasks(now: Date())
                appState.scheduleCompletedTaskCleanup()
            }
        }
    }

    private func pruneExpiredCompletedTasks(now: Date) {
        let expiredIDs = tasks
            .filter { task in
                guard task.isCompleted else { return false }
                let completedAt = task.completedAt ?? task.createdAt
                return now.timeIntervalSince(completedAt) >= completedTaskRetention
            }
            .map(\.id)

        guard !expiredIDs.isEmpty else { return }
        let expiredSet = Set(expiredIDs)
        tasks.removeAll { expiredSet.contains($0.id) }

        for id in expiredIDs {
            NotificationManager.cancelReminder(for: id)
            if calendarSyncEnabled {
                CalendarManager.shared.deleteEvent(for: id)
            }
        }
    }

    /// Daily cleanup for unfinished tasks.
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

            if let s = originalStart, s < todayStart {
                switch unfinishedTaskPolicy {
                case .askMe:
                    break
                case .carryOver:
                    t.isPinned = false
                    t.targetDay = todayStart
                    t.scheduledStart = nil
                    t.scheduledEnd = nil
                    changed = true
                case .autoClear:
                    changed = true
                    NotificationManager.cancelReminder(for: t.id)
                    if calendarSyncEnabled {
                        CalendarManager.shared.deleteEvent(for: t.id)
                    }
                    continue
                }
            } else if wasCreatedYesterday && wasScheduledYesterday && unfinishedTaskPolicy == .autoClear {
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

    func consumeWidgetVoiceRequest() -> Bool {
        guard let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID) else { return false }
        let requested = defaults.bool(forKey: WidgetBridge.voiceRequestKey)
        if requested {
            defaults.set(false, forKey: WidgetBridge.voiceRequestKey)
        }
        return requested
    }

    private func persistWidgetData() {
        guard let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID) else { return }

        let sharedTasks = tasks.map { task in
            WidgetSharedTask(
                id: task.id,
                title: task.title,
                priorityRaw: task.priority.rawValue,
                estimatedMinutes: task.estimatedMinutes,
                isCompleted: task.isCompleted,
                targetDay: task.targetDay,
                scheduledStart: task.scheduledStart,
                scheduledEnd: task.scheduledEnd
            )
        }

        guard let data = try? JSONEncoder().encode(sharedTasks) else { return }
        defaults.set(data, forKey: WidgetBridge.tasksKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "SchedAI_Widget")
        #endif
    }
}
