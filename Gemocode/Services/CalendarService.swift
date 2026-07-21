import EventKit
import Foundation

/// Adds appointments to the user's default calendar using EventKit's
/// iOS 17 write-only scope, with a pure RFC 5545 (.ics) fallback for
/// `ShareLink` when the user declines calendar access. Mirrors the
/// authorization shape of `NotificationService`: request on demand, fail
/// gracefully (never crash) on denial.
enum CalendarService {

    /// Typed failures for the EventKit path. `denied`/`restricted` are
    /// thrown rather than folded into the `Bool` return so a call site can
    /// tell "user said no" apart from "system won't allow it" and offer the
    /// `icsData` fallback with an accurate message.
    enum CalendarError: LocalizedError, Equatable {
        case denied
        case restricted
        case noDefaultCalendar
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .denied:
                String(localized: "Calendar access was denied. You can still export this appointment as a calendar file.")
            case .restricted:
                String(localized: "Calendar access is restricted on this device.")
            case .noDefaultCalendar:
                String(localized: "No default calendar is available to add this event to.")
            case .saveFailed:
                String(localized: "The event could not be saved to your calendar.")
            }
        }
    }

    /// Requests write-only calendar authorization (iOS 17's narrower scope —
    /// this never requests full read/write access) and adds a single event
    /// to the default calendar with a 1-day-before alarm.
    ///
    /// Returns `false` when the user is prompted and declines; throws
    /// `CalendarError` for states that aren't a fresh prompt (already
    /// denied/restricted) or for a save failure. Never crashes on denial.
    @available(iOS 17.0, *)
    static func addEvent(
        title: String,
        date: Date,
        durationMinutes: Int = 30,
        notes: String?,
        location: String?
    ) async throws -> Bool {
        let store = EKEventStore()

        guard try await requestAccess(store: store) else { return false }

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarError.noDefaultCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.notes = notes
        event.location = location
        event.calendar = calendar
        event.addAlarm(EKAlarm(relativeOffset: -86_400)) // 1 day before

        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            throw CalendarError.saveFailed
        }
    }

    /// Resolves current calendar authorization, requesting write-only
    /// access only when it hasn't been decided yet. `.authorized` (the
    /// pre-iOS-17 full-access case) is treated as granted too, in case the
    /// user previously granted full access to this app via some other path.
    @available(iOS 17.0, *)
    private static func requestAccess(store: EKEventStore) async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly, .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        case .denied:
            throw CalendarError.denied
        case .restricted:
            throw CalendarError.restricted
        @unknown default:
            return false
        }
    }

    // MARK: - ICS fallback (no permission required)

    /// Builds a minimal, valid RFC 5545 VCALENDAR/VEVENT payload for
    /// `ShareLink`, so a user who declines calendar access (or just prefers
    /// exporting) can still hand the appointment to any calendar app. Pure
    /// and deterministic: no EventKit, no bare `Date()` — the only "now"
    /// read is DTSTAMP, which RFC 5545 requires and which every VEVENT
    /// naturally has a fresh value for at share time.
    static func icsData(
        title: String,
        date: Date,
        durationMinutes: Int = 30,
        notes: String?,
        location: String?
    ) -> Data {
        let endDate = date.addingTimeInterval(TimeInterval(durationMinutes * 60))

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Gemocode//Calendar Export//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)",
            "DTSTAMP:\(utcTimestamp(for: .now))",
            "DTSTART:\(utcTimestamp(for: date))",
            "DTEND:\(utcTimestamp(for: endDate))",
            "SUMMARY:\(escaped(title))",
        ]
        if let location, !location.isEmpty {
            lines.append("LOCATION:\(escaped(location))")
        }
        if let notes, !notes.isEmpty {
            lines.append("DESCRIPTION:\(escaped(notes))")
        }
        lines.append(contentsOf: [
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            "DESCRIPTION:Reminder",
            "TRIGGER:-P1D",
            "END:VALARM",
            "END:VEVENT",
            "END:VCALENDAR",
        ])

        // RFC 5545 §3.1 requires CRLF line breaks.
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// Formats a date as an RFC 5545 UTC "form #2" timestamp: `YYYYMMDDTHHMMSSZ`.
    private static func utcTimestamp(for date: Date) -> String {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    /// Escapes text per RFC 5545 §3.3.11 (backslash first, so escaping
    /// commas/semicolons/newlines afterward doesn't double-escape the
    /// backslashes those steps introduce).
    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
