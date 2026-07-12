import XCTest
@testable import MediTrack

/// Pure, network-free tests for `QuickAddAIService.draft(fromJSON:now:calendar:)`
/// — the JSON→`QuickAddDraft` mapping and plausibility validation behind the
/// Quick Add AI-assist fallback. `QuickAddAIService.complete` itself (the
/// networking call) is never exercised here. Fixed-date style mirrors
/// `QuickAddParserTests`.
final class QuickAddAIMappingTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Wednesday, January 1, 2025, 09:00 UTC — a fixed, deterministic "now".
    private let now = Date(timeIntervalSince1970: 1_735_722_000)

    private func draft(_ json: String) throws -> QuickAddDraft {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try QuickAddAIService.draft(fromJSON: data, now: now, calendar: calendar)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: Happy path — one per kind

    func testMedicationHappyPath() throws {
        let result = try draft(#"{"kind":"medication","name":"Aspirin","dosage":"100 mg","frequency":"twice daily"}"#)
        XCTAssertEqual(result, .medication(name: "Aspirin", dosage: "100 mg", frequency: "twice daily"))
    }

    func testVitalHappyPath() throws {
        let result = try draft(#"{"kind":"vital","type":"bloodPressure","value":128,"secondary":82}"#)
        XCTAssertEqual(result, .vital(type: .bloodPressure, value: 128, secondary: 82))
    }

    func testVitalWithoutSecondaryHappyPath() throws {
        let result = try draft(#"{"kind":"vital","type":"heartRate","value":72,"secondary":null}"#)
        XCTAssertEqual(result, .vital(type: .heartRate, value: 72, secondary: nil))
    }

    func testSymptomHappyPath() throws {
        let result = try draft(#"{"kind":"symptom","name":"Headache","severity":6}"#)
        XCTAssertEqual(result, .symptom(name: "Headache", severity: 6))
    }

    func testAppointmentHappyPath() throws {
        let result = try draft(#"{"kind":"appointment","title":"Dentist","date":"2025-01-02T15:00:00Z"}"#)
        let expected = try date(year: 2025, month: 1, day: 2, hour: 15)
        XCTAssertEqual(result, .appointment(title: "Dentist", date: expected))
    }

    func testReminderHappyPathWithTime() throws {
        let result = try draft(#"{"kind":"reminder","title":"Take vitamins","time":"2025-01-01T08:00:00Z"}"#)
        let expected = try date(year: 2025, month: 1, day: 1, hour: 8)
        XCTAssertEqual(result, .reminder(title: "Take vitamins", time: expected))
    }

    func testReminderHappyPathWithoutTime() throws {
        let result = try draft(#"{"kind":"reminder","title":"Refill prescription","time":null}"#)
        XCTAssertEqual(result, .reminder(title: "Refill prescription", time: nil))
    }

    // MARK: ISO 8601 parsing

    func testISO8601DateParsingHandlesFractionalSeconds() throws {
        let result = try draft(#"{"kind":"appointment","title":"Checkup","date":"2025-01-02T15:00:00.500Z"}"#)
        let expected = try date(year: 2025, month: 1, day: 2, hour: 15)
        guard case let .appointment(_, date) = result else {
            return XCTFail("Expected an appointment draft")
        }
        XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testAppointmentBadDateStringThrows() {
        XCTAssertThrowsError(try draft(#"{"kind":"appointment","title":"Checkup","date":"not-a-date"}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    // MARK: Out-of-bounds vital rejection

    func testVitalOutOfBoundsRejected() {
        XCTAssertThrowsError(try draft(#"{"kind":"vital","type":"heartRate","value":900}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testVitalBloodPressureMissingSecondaryRejected() {
        XCTAssertThrowsError(try draft(#"{"kind":"vital","type":"bloodPressure","value":128}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testVitalBloodPressureDiastolicOutOfBoundsRejected() {
        XCTAssertThrowsError(
            try draft(#"{"kind":"vital","type":"bloodPressure","value":128,"secondary":900}"#)
        ) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testVitalMissingValueThrows() {
        XCTAssertThrowsError(try draft(#"{"kind":"vital","type":"weight"}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    // MARK: Severity clamping

    func testSeverityClampsAboveTen() throws {
        let result = try draft(#"{"kind":"symptom","name":"Migraine","severity":42}"#)
        XCTAssertEqual(result, .symptom(name: "Migraine", severity: 10))
    }

    func testSeverityClampsBelowOne() throws {
        let result = try draft(#"{"kind":"symptom","name":"Rash","severity":-5}"#)
        XCTAssertEqual(result, .symptom(name: "Rash", severity: 1))
    }

    func testSeverityDefaultsToFiveWhenMissing() throws {
        let result = try draft(#"{"kind":"symptom","name":"Fatigue"}"#)
        XCTAssertEqual(result, .symptom(name: "Fatigue", severity: 5))
    }

    // MARK: Unknown kind / bad enum raw value

    func testUnknownKindThrows() {
        XCTAssertThrowsError(try draft(#"{"kind":"unknown"}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testUnrecognizedKindThrows() {
        XCTAssertThrowsError(try draft(#"{"kind":"banana"}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testBadVitalTypeRawValueThrows() {
        XCTAssertThrowsError(
            try draft(#"{"kind":"vital","type":"bloodOxygenLevel","value":98}"#)
        ) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    // MARK: Missing required fields

    func testMedicationMissingNameThrows() {
        XCTAssertThrowsError(try draft(#"{"kind":"medication","dosage":"10 mg"}"#)) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testAppointmentMissingTitleThrows() {
        XCTAssertThrowsError(
            try draft(#"{"kind":"appointment","date":"2025-01-02T15:00:00Z"}"#)
        ) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try draft("{ this is not valid JSON")) { error in
            XCTAssertTrue(error is QuickAddAIError)
        }
    }

    // MARK: Fence-stripping

    func testFencedJSONIsStripped() throws {
        let fenced = """
            ```json
            {"kind":"medication","name":"Metformin","dosage":"500 mg","frequency":"once daily"}
            ```
            """
        let data = try XCTUnwrap(fenced.data(using: .utf8))
        let result = try QuickAddAIService.draft(fromJSON: data, now: now, calendar: calendar)
        XCTAssertEqual(result, .medication(name: "Metformin", dosage: "500 mg", frequency: "once daily"))
    }

    func testPlainFenceWithoutLanguageTagIsStripped() throws {
        let fenced = """
            ```
            {"kind":"symptom","name":"Nausea","severity":4}
            ```
            """
        let data = try XCTUnwrap(fenced.data(using: .utf8))
        let result = try QuickAddAIService.draft(fromJSON: data, now: now, calendar: calendar)
        XCTAssertEqual(result, .symptom(name: "Nausea", severity: 4))
    }
}
