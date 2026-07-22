import Foundation
import UserNotifications
import os

/// Schedules daily local-notification reminders for medications.
enum NotificationService {

    /// Scheduling is fire-and-forget for callers, but a failed `add` must
    /// not vanish silently — iOS rejects requests for real reasons (the
    /// 64-pending-request cap, malformed triggers) and a user relying on a
    /// medication reminder deserves at least a diagnosable trace.
    private static let logger = Logger(subsystem: "com.ogureq.gemocode", category: "notifications")

    private static func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to schedule notification \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Schedules (or replaces) a repeating daily reminder.
    static func scheduleDailyReminder(id: String, medicationName: String, dosage: String, at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Medication Reminder")
        content.body = dosage.isEmpty
            ? String(localized: "Time to take \(medicationName).")
            : String(localized: "Time to take \(medicationName) (\(dosage)).")
        content.sound = .default

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        add(request)
    }

    /// Schedules (or replaces) a repeating daily reminder with a caller-supplied
    /// title and body. Generic counterpart to the medication-specific overload
    /// above — used by custom reminders (e.g. the "Today" reminders list).
    static func scheduleDailyReminder(id: String, title: String, body: String, at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        add(request)
    }

    /// Schedules a one-shot notification at an absolute time
    /// (e.g. the day before an appointment). Skipped for past dates.
    static func scheduleOneTime(id: String, title: String, body: String, at date: Date) {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancelReminder(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Cancels every pending reminder this app scheduled.
    ///
    /// Per-row deletes cancel their own reminder, but the bulk
    /// `context.delete(model:)` wipes used by Erase All Data and backup
    /// restore don't go through those paths — so without this, "Take your
    /// Vitamin D3" keeps firing for a medication that no longer exists.
    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
