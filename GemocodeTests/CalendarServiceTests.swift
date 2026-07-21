import XCTest
@testable import Gemocode

/// Coverage for `CalendarService.icsData(...)` only. The EventKit path
/// (`addEvent`) needs calendar authorization, which — like the Keychain
/// probed in `AppLockTests` — cannot be granted on CI (unsigned test host,
/// no interactive prompt), so it is intentionally left untested here rather
/// than added and then always skipped. `icsData` is pure and fully
/// deterministic, built from `DateComponents` against a fixed UTC calendar
/// so nothing depends on the wall clock or host time zone.
final class CalendarServiceTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func icsString(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    // MARK: - Structure

    func testIcsDataContainsRequiredCalendarAndEventBoundaries() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: "Cardiology Follow-up",
            date: fixedDate,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("VERSION:2.0"))
        XCTAssertTrue(ics.contains("BEGIN:VEVENT\r\n"))
        XCTAssertTrue(ics.contains("END:VEVENT\r\n"))
        XCTAssertTrue(ics.contains("END:VCALENDAR"))
        // RFC 5545 §3.1 line breaks are CRLF, not bare LF.
        XCTAssertFalse(ics.contains("\n") && !ics.contains("\r\n"))
    }

    func testIcsDataIncludesUIDAndDTSTAMP() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: "Checkup",
            date: fixedDate,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains("UID:"))
        XCTAssertTrue(ics.contains("DTSTAMP:"))
    }

    // MARK: - Date formatting (fixed, deterministic)

    func testIcsDataDTSTARTAndDTENDUseExpectedUTCTimestampFormat() throws {
        let start = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30, second: 0)
        let ics = try icsString(CalendarService.icsData(
            title: "Dermatology Visit",
            date: start,
            durationMinutes: 45,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains("DTSTART:20260721T143000Z"))
        // 14:30 + 45 minutes = 15:15.
        XCTAssertTrue(ics.contains("DTEND:20260721T151500Z"))
    }

    func testIcsDataDefaultDurationIsThirtyMinutes() throws {
        let start = try date(year: 2026, month: 1, day: 1, hour: 9, minute: 0)
        let ics = try icsString(CalendarService.icsData(
            title: "Annual Physical",
            date: start,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains("DTSTART:20260101T090000Z"))
        XCTAssertTrue(ics.contains("DTEND:20260101T093000Z"))
    }

    // MARK: - Alarm

    func testIcsDataIncludesOneDayBeforeAlarm() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: "Checkup",
            date: fixedDate,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains("BEGIN:VALARM"))
        XCTAssertTrue(ics.contains("TRIGGER:-P1D"))
        XCTAssertTrue(ics.contains("END:VALARM"))
    }

    // MARK: - Optional fields

    func testIcsDataOmitsLocationAndDescriptionWhenNilOrEmpty() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: "Checkup",
            date: fixedDate,
            notes: "",
            location: nil
        ))

        XCTAssertFalse(ics.contains("LOCATION:"))
        XCTAssertFalse(ics.contains("DESCRIPTION:"))
    }

    func testIcsDataIncludesLocationAndDescriptionWhenProvided() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: "Checkup",
            date: fixedDate,
            notes: "Bring prior lab results.",
            location: "123 Main St, Suite 4"
        ))

        XCTAssertTrue(ics.contains("LOCATION:123 Main St\\, Suite 4"))
        XCTAssertTrue(ics.contains("DESCRIPTION:Bring prior lab results."))
    }

    // MARK: - Text escaping (RFC 5545 §3.3.11)

    func testIcsDataEscapesCommasSemicolonsAndNewlinesInSummary() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: "Follow-up, cardiology; urgent\nplease confirm",
            date: fixedDate,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains("SUMMARY:Follow-up\\, cardiology\\; urgent\\nplease confirm"))
        // The escaped line itself must not contain a raw newline mid-value.
        XCTAssertFalse(ics.contains("urgent\nplease"))
    }

    func testIcsDataEscapesBackslashesBeforeOtherEscaping() throws {
        let fixedDate = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let ics = try icsString(CalendarService.icsData(
            title: #"Path\Test, value"#,
            date: fixedDate,
            notes: nil,
            location: nil
        ))

        XCTAssertTrue(ics.contains(#"SUMMARY:Path\\Test\, value"#))
    }
}
