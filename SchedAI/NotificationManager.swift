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

    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    struct ScheduleResult: Equatable {
        let queued: Int
        let skippedPast: Int
        let skippedLimit: Int
        let failed: Int
        let firstErrorMessage: String?
    }

    private struct ReminderPlan {
        let requests: [UNNotificationRequest]
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
        let plan = reminderPlan(for: tasks, minutesBefore: minutesBefore)
        for request in plan.requests {
            center.add(request) { error in
                #if DEBUG
                if let error {
                    print("SchedAI reminder scheduling failed: \(error.localizedDescription)")
                }
                #endif
            }
        }
        return ScheduleResult(
            queued: plan.requests.count,
            skippedPast: plan.skippedPast,
            skippedLimit: plan.skippedLimit,
            failed: 0,
            firstErrorMessage: nil
        )
    }

    /// Schedule reminders and wait for UserNotifications to report add failures.
    @discardableResult
    static func scheduleRemindersReportingFailures(for tasks: [TaskItem], minutesBefore: Int) async -> ScheduleResult {
        let center = UNUserNotificationCenter.current()
        let plan = reminderPlan(for: tasks, minutesBefore: minutesBefore)
        var queued = 0
        var failed = 0
        var firstErrorMessage: String? = nil

        for request in plan.requests {
            let error = await add(request, to: center)
            if let error {
                failed += 1
                firstErrorMessage = firstErrorMessage ?? error.localizedDescription
                #if DEBUG
                print("SchedAI reminder scheduling failed: \(error.localizedDescription)")
                #endif
            } else {
                queued += 1
            }
        }

        return ScheduleResult(
            queued: queued,
            skippedPast: plan.skippedPast,
            skippedLimit: plan.skippedLimit,
            failed: failed,
            firstErrorMessage: firstErrorMessage
        )
    }

    private static func reminderPlan(for tasks: [TaskItem], minutesBefore: Int) -> ReminderPlan {
        let now = Date()
        let candidates = tasks
            .compactMap { task -> (task: TaskItem, triggerDate: Date)? in
                guard let start = task.scheduledStart else { return nil }
                guard task.canAutoSchedule(on: start) else { return nil }
                let triggerDate = start.addingTimeInterval(TimeInterval(-minutesBefore * 60))
                guard triggerDate > now else { return nil }
                return (task, triggerDate)
            }
            .sorted { $0.triggerDate < $1.triggerDate }

        let scheduleableTasks = Array(candidates.prefix(maximumScheduledReminders))
        let eligibleScheduledCount = tasks.filter { task in
            guard let start = task.scheduledStart else { return false }
            return task.canAutoSchedule(on: start)
        }.count
        let skippedPast = max(0, eligibleScheduledCount - candidates.count)
        let skippedLimit = max(0, candidates.count - scheduleableTasks.count)

        let requests = scheduleableTasks.compactMap { item -> UNNotificationRequest? in
            let t = item.task
            guard let start = t.scheduledStart else { return nil }

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: item.triggerDate
            )

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let content = UNMutableNotificationContent()
            let startTime = start.formatted(date: .omitted, time: .shortened)
            let priorityText = "\(t.priority.displayName) Priority"
            content.title = "Task: \(t.title)"
            content.subtitle = "\(startTime) • \(priorityText)"
            content.body = "Time: \(startTime) • Priority: \(t.priority.displayName)"
            content.sound = .default
            content.interruptionLevel = .active

            return UNNotificationRequest(
                identifier: reminderIdentifier(for: t.id),
                content: content,
                trigger: trigger
            )
        }

        return ReminderPlan(requests: requests, skippedPast: skippedPast, skippedLimit: skippedLimit)
    }

    private static func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async -> Error? {
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private static func reminderIdentifier(for id: UUID) -> String {
        "\(reminderIdentifierPrefix)\(id.uuidString)"
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
