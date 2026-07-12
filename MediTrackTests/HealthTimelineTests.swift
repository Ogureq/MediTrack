import XCTest
import SwiftData
@testable import MediTrack

/// Coverage for `HealthTimeline.events(...)`: the deterministic, template-only
/// timeline generator. Mirrors the `AnalysisEngineTests` pattern — fixed
/// dates built from `DateComponents`, an in-memory `ModelContainer`, and no
/// force-unwraps besides `XCTUnwrap`.
@MainActor
final class HealthTimelineTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: HealthProfile.self,
                 MedicalReport.self,
                 LabResult.self,
                 ReportAttachment.self,
                 VitalSample.self,
                 Medication.self,
                 HealthGoal.self,
                 SymptomEntry.self,
                 Appointment.self,
                 ScoreSnapshot.self,
                 Reminder.self,
                 ReminderCompletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_752_000_000) // deterministic reference instant

    /// Builds a deterministic date from components so tests never depend on
    /// the wall clock.
    private func date(year: Int, month: Int, day: Int, hour: Int = 9) throws -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return try XCTUnwrap(Calendar.current.date(from: comps))
    }

    // MARK: Lab crossing out of range

    func testLabCrossingOutOfRangeProducesImportantEventWithBothValues() throws {
        let earlierDate = try date(year: 2025, month: 1, day: 10)
        let laterDate = try date(year: 2025, month: 3, day: 10)

        let firstReport = MedicalReport(title: "Panel A", category: .labReport, date: earlierDate)
        let secondReport = MedicalReport(title: "Panel B", category: .labReport, date: laterDate)
        context.insert(firstReport)
        context.insert(secondReport)
        firstReport.labResults.append(LabResult(catalogID: "totalCholesterol", value: 180, unit: "mg/dL", date: earlierDate))
        secondReport.labResults.append(LabResult(catalogID: "totalCholesterol", value: 245, unit: "mg/dL", date: laterDate))
        try context.save()

        let events = HealthTimeline.events(
            reports: [firstReport, secondReport],
            vitals: [],
            scores: [],
            medications: [],
            now: laterDate
        )

        let crossing = try XCTUnwrap(events.first { $0.category == .lab && $0.significance == .important })
        XCTAssertTrue(crossing.detail.contains("180"), "Expected previous value 180 in caption: \(crossing.detail)")
        XCTAssertTrue(crossing.detail.contains("245"), "Expected new value 245 in caption: \(crossing.detail)")
        XCTAssertEqual(crossing.date, laterDate)
    }

    // MARK: Lab returning into range

    func testLabReturningIntoRangeProducesNotableEvent() throws {
        let earlierDate = try date(year: 2025, month: 2, day: 1)
        let laterDate = try date(year: 2025, month: 5, day: 1)

        let firstReport = MedicalReport(title: "Panel A", category: .labReport, date: earlierDate)
        let secondReport = MedicalReport(title: "Panel B", category: .labReport, date: laterDate)
        context.insert(firstReport)
        context.insert(secondReport)
        // LDL reference range is 0...99; 150 is out of range, 90 is back in range.
        firstReport.labResults.append(LabResult(catalogID: "ldlCholesterol", value: 150, unit: "mg/dL", date: earlierDate))
        secondReport.labResults.append(LabResult(catalogID: "ldlCholesterol", value: 90, unit: "mg/dL", date: laterDate))
        try context.save()

        let events = HealthTimeline.events(
            reports: [firstReport, secondReport],
            vitals: [],
            scores: [],
            medications: [],
            now: laterDate
        )

        let backInRange = try XCTUnwrap(events.first {
            $0.category == .lab && $0.title.localizedCaseInsensitiveContains("returned")
        })
        XCTAssertEqual(backInRange.significance, .notable)
        XCTAssertTrue(backInRange.detail.contains("150"))
        XCTAssertTrue(backInRange.detail.contains("90"))
    }

    // MARK: Score deltas

    func testScoreDeltaAtLeastFiveProducesEventAndSmallerDeltaDoesNot() throws {
        let day1 = try date(year: 2025, month: 5, day: 1)
        let day2 = try date(year: 2025, month: 5, day: 8)
        let day3 = try date(year: 2025, month: 5, day: 15)

        let snapshot1 = ScoreSnapshot(date: day1, score: 70)
        let snapshot2 = ScoreSnapshot(date: day2, score: 76) // delta of 6 -> event
        let snapshot3 = ScoreSnapshot(date: day3, score: 79) // delta of 3 -> no event
        [snapshot1, snapshot2, snapshot3].forEach { context.insert($0) }
        try context.save()

        let events = HealthTimeline.events(
            reports: [],
            vitals: [],
            scores: [snapshot1, snapshot2, snapshot3],
            medications: [],
            now: day3
        )

        let scoreEvents = events.filter { $0.category == .score }
        XCTAssertEqual(scoreEvents.count, 1)
        let event = try XCTUnwrap(scoreEvents.first)
        XCTAssertEqual(event.date, day2)
        XCTAssertEqual(event.significance, .notable)
        XCTAssertTrue(event.detail.contains("70"))
        XCTAssertTrue(event.detail.contains("76"))
    }

    // MARK: Medication start/end

    func testMedicationStartAndEndProduceRoutineEvents() throws {
        let start = try date(year: 2025, month: 2, day: 1)
        let end = try date(year: 2025, month: 6, day: 1)

        let medication = Medication(name: "Lisinopril", dosage: "10 mg", startDate: start, endDate: end)
        context.insert(medication)
        try context.save()

        let events = HealthTimeline.events(
            reports: [],
            vitals: [],
            scores: [],
            medications: [medication],
            now: end
        )

        let medicationEvents = events.filter { $0.category == .medication }
        XCTAssertEqual(medicationEvents.count, 2)
        XCTAssertTrue(medicationEvents.allSatisfy { $0.significance == .routine })
        XCTAssertTrue(medicationEvents.contains {
            $0.date == start && $0.title.localizedCaseInsensitiveContains("started")
        })
        XCTAssertTrue(medicationEvents.contains {
            $0.date == end && $0.title.localizedCaseInsensitiveContains("ended")
        })
    }

    func testMedicationWithoutEndDateProducesOnlyStartEvent() throws {
        let start = try date(year: 2025, month: 3, day: 1)
        let medication = Medication(name: "Metformin", startDate: start)
        context.insert(medication)
        try context.save()

        let events = HealthTimeline.events(
            reports: [],
            vitals: [],
            scores: [],
            medications: [medication],
            now: start
        )

        let medicationEvents = events.filter { $0.category == .medication }
        XCTAssertEqual(medicationEvents.count, 1)
        XCTAssertEqual(medicationEvents.first?.title.localizedCaseInsensitiveContains("started"), true)
    }

    // MARK: Empty input

    func testEmptyInputsProduceNoEvents() {
        let events = HealthTimeline.events(
            reports: [],
            vitals: [],
            scores: [],
            medications: [],
            now: fixedNow
        )
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: Ordering

    func testEventsAreSortedNewestFirst() throws {
        let day1 = try date(year: 2025, month: 1, day: 1)
        let day2 = try date(year: 2025, month: 4, day: 1)
        let day3 = try date(year: 2025, month: 8, day: 1)

        let reportA = MedicalReport(title: "Checkup A", category: .consultation, date: day1)
        let reportB = MedicalReport(title: "Checkup B", category: .consultation, date: day2)
        let reportC = MedicalReport(title: "Checkup C", category: .consultation, date: day3)
        [reportA, reportB, reportC].forEach { context.insert($0) }
        try context.save()

        let events = HealthTimeline.events(
            reports: [reportA, reportB, reportC],
            vitals: [],
            scores: [],
            medications: [],
            now: day3
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted(by: >))
        XCTAssertEqual(events.first?.date, day3)
        XCTAssertEqual(events.last?.date, day1)
        XCTAssertTrue(events.allSatisfy { $0.category == .report && $0.significance == .routine })
    }
}
