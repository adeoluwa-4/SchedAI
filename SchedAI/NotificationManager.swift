//
//  NotificationManager.swift
//  SchedAI
//
//  Created by Adeoluwa Adekoya on 9/21/25.
//

import Foundation
import UserNotifications

enum NotificationManager {
    private static let maximumScheduledReminders = 60
    private static let reminderIdentifierPrefix = "schedai.task."

    private enum DefaultsKey {
        static let showTaskTitlesInNotifications = "showTaskTitlesInNotifications"
    }

    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    struct ScheduleResult: Equatable {
        let queued: Int
        let skippedPast: Int
        let skippedLimit: Int
    }

    /// Read current notification authorization status without prompting.
    static func authorizationStatus(completion: @escaping (AuthorizationState) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: AuthorizationState
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                state = .authorized
            case .denied:
                state = .denied
            case .notDetermined:
                state = .notDetermined
            @unknown default:
                state = .denied
            }
            DispatchQueue.main.async {
                completion(state)
            }
        }
    }

    /// Request notification permissions (explicit completion avoids ambiguous overloads).
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
    }

    /// Remove notifications (explicit args avoid ambiguous overloads).
    static func clearAll(delivered: Bool, pending: Bool) {
        let c = UNUserNotificationCenter.current()
        if delivered { c.removeAllDeliveredNotifications() }
        if pending { c.removeAllPendingNotificationRequests() }
    }

    /// Cancel a single scheduled reminder by task id.
    static func cancelReminder(for id: UUID) {
        let legacyKey = id.uuidString
        let key = reminderIdentifier(for: id)
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [key, legacyKey])
        c.removeDeliveredNotifications(withIdentifiers: [key, legacyKey])
    }

    /// Schedule reminders N minutes before each scheduled task.
    @discardableResult
    static func scheduleReminders(for tasks: [TaskItem], minutesBefore: Int) -> ScheduleResult {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let candidates = tasks
            .compactMap { task -> (task: TaskItem, triggerDate: Date)? in
                guard let start = task.scheduledStart else { return nil }
                let triggerDate = start.addingTimeInterval(TimeInterval(-minutesBefore * 60))
                guard triggerDate > now else { return nil }
                return (task, triggerDate)
            }
            .sorted { $0.triggerDate < $1.triggerDate }

        let scheduleableTasks = Array(candidates.prefix(maximumScheduledReminders))
        let skippedPast = max(0, tasks.filter { $0.scheduledStart != nil }.count - candidates.count)
        let skippedLimit = max(0, candidates.count - scheduleableTasks.count)

        for item in scheduleableTasks {
            let t = item.task
            guard let start = t.scheduledStart else { continue }

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: item.triggerDate
            )

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let content = UNMutableNotificationContent()
            let priorityDot = reminderDot(for: t.priority)
            let priorityText = "\(t.priority.displayName) Priority"
            if shouldShowTaskTitles() {
                content.title = "\(priorityDot) \(priorityText): \(t.title)"
                content.subtitle = "Starts at \(start.formatted(date: .omitted, time: .shortened))"
                content.body = "Starts in about \(minutesBefore) min (\(t.estimatedMinutes)m)"
            } else {
                content.title = "SchedAI Reminder"
                content.subtitle = "Starts at \(start.formatted(date: .omitted, time: .shortened))"
                content.body = "\(priorityText) task starts in about \(minutesBefore) min."
            }
            content.sound = .default
            content.interruptionLevel = .active

            let req = UNNotificationRequest(
                identifier: reminderIdentifier(for: t.id),
                content: content,
                trigger: trigger
            )

            center.add(req) { error in
                #if DEBUG
                if let error {
                    print("SchedAI reminder scheduling failed: \(error.localizedDescription)")
                }
                #endif
            }
        }

        return ScheduleResult(queued: scheduleableTasks.count, skippedPast: skippedPast, skippedLimit: skippedLimit)
    }

    private static func reminderIdentifier(for id: UUID) -> String {
        "\(reminderIdentifierPrefix)\(id.uuidString)"
    }

    private static func shouldShowTaskTitles() -> Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.showTaskTitlesInNotifications)
    }

    private static func reminderDot(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "🔴"
        case .medium: return "🟡"
        case .low: return "🟢"
        }
    }

    static func sendTestReminder(inSeconds seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "SchedAI Test"
        content.body = "This is your test notification."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(5, seconds),
            repeats: false
        )

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(req) { error in
            #if DEBUG
            if let error {
                print("SchedAI test reminder failed: \(error.localizedDescription)")
            }
            #endif
        }
    }
}
