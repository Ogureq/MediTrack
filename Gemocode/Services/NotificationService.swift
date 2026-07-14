import Foundation
import UserNotifications

/// Schedules daily local-notification reminders for medications.
enum NotificationService {

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
        content.title = "Medication Reminder"
        content.body = dosage.isEmpty
            ? "Time to take \(medicationName)."
            : "Time to take \(medicationName) (\(dosage))."
        content.sound = .default

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
        UNUserNotificationCenter.current().add(request)
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
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    static func cancelReminder(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
