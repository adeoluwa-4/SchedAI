//
//  NotificationManager.swift
//  SchedAI
//
//  Created by Adeoluwa Adekoya on 9/21/25.
//

import Foundation
import UserNotifications

enum NotificationManager {

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
    static func scheduleReminders(for tasks: [TaskItem], minutesBefore: Int) {
        let center = UNUserNotificationCenter.current()

        for t in tasks {
            guard let start = t.scheduledStart else { continue }

            let triggerDate = start.addingTimeInterval(TimeInterval(-minutesBefore * 60))
            guard triggerDate > Date() else { continue }

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: triggerDate
            )

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "Upcoming: \(t.title)"
            content.body = "Starts in about \(minutesBefore) min (\(t.estimatedMinutes)m)"
            content.sound = .default

            let req = UNNotificationRequest(
                identifier: t.id.uuidString,
                content: content,
                trigger: trigger
            )

            center.add(req)
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
