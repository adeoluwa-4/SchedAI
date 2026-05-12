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

    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
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
            completion(state)
        }
    }

    /// Request notification permissions (explicit completion avoids ambiguous overloads).
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                completion(granted)
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
        let key = id.uuidString
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [key])
        c.removeDeliveredNotifications(withIdentifiers: [key])
    }

    /// Schedule reminders N minutes before each scheduled task.
    @discardableResult
    static func scheduleReminders(for tasks: [TaskItem], minutesBefore: Int) -> Int {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let scheduleableTasks = tasks
            .compactMap { task -> (task: TaskItem, triggerDate: Date)? in
                guard let start = task.scheduledStart else { return nil }
                let triggerDate = start.addingTimeInterval(TimeInterval(-minutesBefore * 60))
                guard triggerDate > now else { return nil }
                return (task, triggerDate)
            }
            .sorted { $0.triggerDate < $1.triggerDate }
            .prefix(maximumScheduledReminders)

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
            content.title = "\(priorityDot) \(priorityText): \(t.title)"
            content.subtitle = "Starts at \(start.formatted(date: .omitted, time: .shortened))"
            content.body = "Starts in about \(minutesBefore) min (\(t.estimatedMinutes)m)"
            content.sound = .default
            content.interruptionLevel = .active

            let req = UNNotificationRequest(
                identifier: t.id.uuidString,
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

        return scheduleableTasks.count
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

        UNUserNotificationCenter.current().add(req)
    }
}
