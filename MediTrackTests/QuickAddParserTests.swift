import XCTest
@testable import MediTrack

/// Coverage for `QuickAddParser.parse(_:now:calendar:)`: every recognized
/// vocabulary branch (vitals, medication, symptoms, appointments, reminders),
/// the vital > medication > symptom > appointment > reminder priority order,
/// unit conversions (lb→kg, °F→°C), implausible-value rejection, severity
/// clamping, and relative date math. All dates are built from `DateComponents`
/// against a fixed UTC calendar so nothing depends on the wall clock.
final class QuickAddParserTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Wednesday, January 1, 2025, 09:00 UTC — a fixed, deterministic "now".
    private let now = Date(timeIntervalSince1970: 1_735_722_000)

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

    private func parse(_ text: String) -> QuickAddDraft? {
        QuickAddParser.parse(text, now: now, calendar: calendar)
    }

    private func vitalValue(_ draft: QuickAddDraft?) -> (type: VitalType, value: Double, secondary: Double?)? {
        guard case let .vital(type, value, secondary) = draft else { return nil }
        return (type, value, secondary)
    }

    // MARK: Vitals — blood pressure

    func testBloodPressureSlashFormat() {
        XCTAssertEqual(parse("bp 128/82"), .vital(type: .bloodPressure, value: 128, secondary: 82))
    }

    func testBloodPressureOverWordFormat() {
        XCTAssertEqual(
            parse("blood pressure 128 over 82"),
            .vital(type: .bloodPressure, value: 128, secondary: 82)
        )
    }

    func testBloodPressureImplausibleValuesRejected() {
        XCTAssertNil(parse("bp 500/300"))
    }

    // MARK: Vitals — weight (unit conversion)

    func testWeightKilogramsExplicit() {
        XCTAssertEqual(parse("weight 71.5 kg"), .vital(type: .weight, value: 71.5, secondary: nil))
    }

    func testWeightPoundsConvertsToCanonicalKilograms() {
        let expectedKg = 155.0 / 2.204_62
        let extracted = vitalValue(parse("155 lb"))
        XCTAssertEqual(extracted?.type, .weight)
        XCTAssertEqual(extracted?.value ?? -1, expectedKg, accuracy: 0.01)
        XCTAssertNil(extracted?.secondary)
    }

    // MARK: Vitals — heart rate

    func testHeartRateShortForm() {
        XCTAssertEqual(parse("hr 72"), .vital(type: .heartRate, value: 72, secondary: nil))
    }

    func testHeartRatePulseWithBpmSuffix() {
        XCTAssertEqual(parse("pulse 72 bpm"), .vital(type: .heartRate, value: 72, secondary: nil))
    }

    func testHeartRateFullPhrase() {
        XCTAssertEqual(parse("heart rate 72"), .vital(type: .heartRate, value: 72, secondary: nil))
    }

    // MARK: Vitals — temperature (unit conversion)

    func testTemperatureCelsiusPassesThroughUnchanged() {
        XCTAssertEqual(parse("temp 37.2"), .vital(type: .temperature, value: 37.2, secondary: nil))
    }

    func testTemperatureFahrenheitConvertsToCelsius() {
        // 100.4°F is exactly 38.0°C.
        let extracted = vitalValue(parse("temp 100.4"))
        XCTAssertEqual(extracted?.type, .temperature)
        XCTAssertEqual(extracted?.value ?? -1, 38.0, accuracy: 0.01)
    }

    // MARK: Vitals — glucose

    func testGlucoseKeyword() {
        XCTAssertEqual(parse("glucose 95"), .vital(type: .bloodGlucose, value: 95, secondary: nil))
    }

    func testBloodSugarPhrase() {
        XCTAssertEqual(parse("blood sugar 95"), .vital(type: .bloodGlucose, value: 95, secondary: nil))
    }

    // MARK: Vitals — oxygen saturation

    func testOxygenSaturationSpo2Keyword() {
        XCTAssertEqual(parse("spo2 98"), .vital(type: .oxygenSaturation, value: 98, secondary: nil))
    }

    func testOxygenSaturationPercentPhrase() {
        XCTAssertEqual(parse("oxygen 98%"), .vital(type: .oxygenSaturation, value: 98, secondary: nil))
    }

    // MARK: Vitals — respiratory rate & sleep

    func testRespiratoryRate() {
        XCTAssertEqual(parse("resp rate 16"), .vital(type: .respiratoryRate, value: 16, secondary: nil))
    }

    func testSleepHours() {
        XCTAssertEqual(parse("slept 7.5 hours"), .vital(type: .sleepHours, value: 7.5, secondary: nil))
    }

    // MARK: Medication

    func testMedicationLeadingTakeWithFusedDosage() {
        XCTAssertEqual(
            parse("take aspirin 100mg"),
            .medication(name: "Aspirin", dosage: "100 mg", frequency: "")
        )
    }

    func testMedicationStartWithTwiceDailyFrequency() {
        XCTAssertEqual(
            parse("start metformin 500 mg twice daily"),
            .medication(name: "Metformin", dosage: "500 mg", frequency: "twice daily")
        )
    }

    func testMedicationNoLeadVerbOnceDaily() {
        XCTAssertEqual(
            parse("Lisinopril 10mg once daily"),
            .medication(name: "Lisinopril", dosage: "10 mg", frequency: "once daily")
        )
    }

    func testMedicationAsNeededFrequency() {
        XCTAssertEqual(
            parse("ibuprofen 200 mg as needed"),
            .medication(name: "Ibuprofen", dosage: "200 mg", frequency: "as needed")
        )
    }

    func testMedicationEveryNightFrequency() {
        XCTAssertEqual(
            parse("melatonin 5mg every night"),
            .medication(name: "Melatonin", dosage: "5 mg", frequency: "every night")
        )
    }

    func testMedicationTabletCount() {
        XCTAssertEqual(
            parse("take ibuprofen 2 tablets"),
            .medication(name: "Ibuprofen", dosage: "2 tablets", frequency: "")
        )
    }

    func testMedicationMicrogramUnit() {
        XCTAssertEqual(
            parse("take levothyroxine 10 mcg"),
            .medication(name: "Levothyroxine", dosage: "10 mcg", frequency: "")
        )
    }

    func testMedicationMilliliterUnit() {
        XCTAssertEqual(
            parse("amoxicillin 5ml"),
            .medication(name: "Amoxicillin", dosage: "5 ml", frequency: "")
        )
    }

    func testMedicationNameAfterDosageWhenNothingPrecedesIt() {
        XCTAssertEqual(
            parse("100mg aspirin"),
            .medication(name: "Aspirin", dosage: "100 mg", frequency: "")
        )
    }

    // MARK: Symptoms

    func testSymptomSimpleVocabularyDefaultsSeverityToFive() {
        XCTAssertEqual(parse("fatigue"), .symptom(name: "Fatigue", severity: 5))
    }

    func testSymptomSeverityKeyword() {
        XCTAssertEqual(parse("headache severity 8"), .symptom(name: "Headache", severity: 8))
    }

    func testSymptomLevelKeyword() {
        XCTAssertEqual(parse("migraine level 3"), .symptom(name: "Migraine", severity: 3))
    }

    func testSymptomQualifiedPainWithSlashSeverity() {
        XCTAssertEqual(parse("back pain 7/10"), .symptom(name: "Back Pain", severity: 7))
    }

    func testSymptomSeverityClampsAboveTen() {
        XCTAssertEqual(parse("chest pain severity 15"), .symptom(name: "Chest Pain", severity: 10))
    }

    func testSymptomSeverityClampsBelowOne() {
        XCTAssertEqual(parse("rash level 0"), .symptom(name: "Rash", severity: 1))
    }

    // MARK: Appointments — relative dates & time

    func testAppointmentTomorrowWithExplicitTime() throws {
        let expected = try date(year: 2025, month: 1, day: 2, hour: 15)
        XCTAssertEqual(parse("dentist checkup tomorrow at 3pm"), .appointment(title: "Dentist checkup", date: expected))
    }

    func testAppointmentNextWeekDefaultsToTenAM() throws {
        let expected = try date(year: 2025, month: 1, day: 8, hour: 10)
        XCTAssertEqual(parse("doctor appointment next week"), .appointment(title: "Doctor appointment", date: expected))
    }

    func testAppointmentInNDays() throws {
        let expected = try date(year: 2025, month: 1, day: 3, hour: 10)
        XCTAssertEqual(parse("checkup in 2 days"), .appointment(title: "Checkup", date: expected))
    }

    func testAppointmentInNWeeks() throws {
        let expected = try date(year: 2025, month: 1, day: 15, hour: 10)
        XCTAssertEqual(parse("follow-up in 2 weeks"), .appointment(title: "Follow-up", date: expected))
    }

    func testAppointmentWeekdayResolvesToThisWeeksOccurrence() throws {
        // "now" is Wednesday Jan 1, 2025 — the next Friday is Jan 3.
        let expected = try date(year: 2025, month: 1, day: 3, hour: 10)
        XCTAssertEqual(parse("appointment on friday"), .appointment(title: "Appointment", date: expected))
    }

    func testAppointmentWeekdayWrapsToNextWeekWhenEarlierInWeek() throws {
        // "now" is Wednesday Jan 1, 2025 — the next Monday is Jan 6.
        let expected = try date(year: 2025, month: 1, day: 6, hour: 10)
        XCTAssertEqual(parse("appointment on monday"), .appointment(title: "Appointment", date: expected))
    }

    // MARK: Reminders

    func testReminderRemindMeToWithTime() throws {
        let expected = try date(year: 2025, month: 1, day: 1, hour: 8)
        XCTAssertEqual(parse("remind me to take vitamins at 8am"), .reminder(title: "Take vitamins", time: expected))
    }

    func testReminderColonPrefixWithoutTime() {
        XCTAssertEqual(parse("reminder: refill prescription"), .reminder(title: "Refill prescription", time: nil))
    }

    // MARK: Priority ordering

    func testVitalWinsOverMedicationWhenBothPresent() {
        XCTAssertEqual(
            parse("bp 128/82 after taking aspirin 100mg"),
            .vital(type: .bloodPressure, value: 128, secondary: 82)
        )
    }

    func testMedicationWinsOverReminderWhenBothPresent() {
        XCTAssertEqual(
            parse("remind me to take metformin 500mg"),
            .medication(name: "Metformin", dosage: "500 mg", frequency: "")
        )
    }

    // MARK: Nil for unrecognized input

    func testNilForGibberish() {
        XCTAssertNil(parse("hello world"))
    }

    func testNilForEmptyString() {
        XCTAssertNil(parse(""))
    }

    func testNilForWhitespaceOnlyString() {
        XCTAssertNil(parse("   \n  "))
    }
}
