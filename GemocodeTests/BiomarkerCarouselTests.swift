import XCTest
import SwiftData
@testable import Gemocode

/// Coverage for `BiomarkerGrouping.series(from:)`: the pure grouping/ordering
/// function behind the dashboard biomarker carousel. Mirrors the
/// `HealthTimelineTests` pattern — fixed dates built from `DateComponents`,
/// a retained in-memory `ModelContainer`, and no force-unwraps besides
/// `XCTUnwrap`. No UI is exercised here.
@MainActor
final class BiomarkerCarouselTests: XCTestCase {

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

    /// Inserts a fresh `MedicalReport` and attaches `result` to it, so the
    /// in-memory context can save it — mirrors how every other test in this
    /// suite creates `LabResult` values.
    private func attach(_ result: LabResult, in title: String, date: Date) {
        let report = MedicalReport(title: title, category: .labReport, date: date)
        context.insert(report)
        report.labResults.append(result)
    }

    // MARK: Empty input

    func testEmptyInputProducesEmptyOutput() {
        XCTAssertTrue(BiomarkerGrouping.series(from: []).isEmpty)
    }

    // MARK: Grouping by catalogID

    func testResultsWithSameCatalogIDGroupIntoOneSeriesRegardlessOfCase() throws {
        let day1 = try date(year: 2025, month: 1, day: 10)
        let day2 = try date(year: 2025, month: 4, day: 10)

        let first = LabResult(catalogID: "ldlCholesterol", value: 150, unit: "mg/dL", date: day1)
        let second = LabResult(catalogID: "LDLCHOLESTEROL", value: 90, unit: "mg/dL", date: day2)
        attach(first, in: "Panel A", date: day1)
        attach(second, in: "Panel B", date: day2)
        try context.save()

        let series = BiomarkerGrouping.series(from: [first, second])

        XCTAssertEqual(series.count, 1)
        let only = try XCTUnwrap(series.first)
        XCTAssertEqual(only.id, "ldlcholesterol")
        XCTAssertEqual(only.points.count, 2)
        XCTAssertEqual(only.name, "LDL Cholesterol")
    }

    // MARK: Custom-name fallback grouping

    func testCustomTestsWithoutCatalogIDGroupByLowercasedCustomName() throws {
        let day1 = try date(year: 2025, month: 2, day: 1)
        let day2 = try date(year: 2025, month: 6, day: 1)

        let first = LabResult(customName: "My Custom Marker", value: 5, unit: "u", date: day1)
        let second = LabResult(customName: "MY CUSTOM MARKER", value: 7, unit: "u", date: day2)
        attach(first, in: "Panel A", date: day1)
        attach(second, in: "Panel B", date: day2)
        try context.save()

        let series = BiomarkerGrouping.series(from: [first, second])

        XCTAssertEqual(series.count, 1)
        let only = try XCTUnwrap(series.first)
        XCTAssertEqual(only.id, "custom:my custom marker")
        XCTAssertEqual(only.points.count, 2)
        XCTAssertEqual(only.unit, "u")
    }

    func testDistinctCustomNamesProduceSeparateSeries() throws {
        let day = try date(year: 2025, month: 3, day: 1)

        let first = LabResult(customName: "Marker One", value: 1, unit: "u", date: day)
        let second = LabResult(customName: "Marker Two", value: 2, unit: "u", date: day)
        attach(first, in: "Panel A", date: day)
        attach(second, in: "Panel B", date: day)
        try context.save()

        let series = BiomarkerGrouping.series(from: [first, second])

        XCTAssertEqual(series.count, 2)
        XCTAssertTrue(series.contains { $0.id == "custom:marker one" })
        XCTAssertTrue(series.contains { $0.id == "custom:marker two" })
    }

    // MARK: Ascending point order

    func testPointsWithinASeriesAreSortedAscendingByDate() throws {
        let earliest = try date(year: 2025, month: 1, day: 1)
        let middle = try date(year: 2025, month: 3, day: 1)
        let latest = try date(year: 2025, month: 6, day: 1)

        // Insert out of chronological order.
        let r2 = LabResult(catalogID: "hemoglobin", value: 14.0, unit: "g/dL", date: middle)
        let r3 = LabResult(catalogID: "hemoglobin", value: 15.0, unit: "g/dL", date: latest)
        let r1 = LabResult(catalogID: "hemoglobin", value: 13.0, unit: "g/dL", date: earliest)
        attach(r2, in: "Panel", date: middle)
        attach(r3, in: "Panel", date: latest)
        attach(r1, in: "Panel", date: earliest)
        try context.save()

        let series = BiomarkerGrouping.series(from: [r2, r3, r1])

        let only = try XCTUnwrap(series.first)
        XCTAssertEqual(only.points.map(\.date), [earliest, middle, latest])
        XCTAssertEqual(only.points.map(\.value), [13.0, 14.0, 15.0])
        XCTAssertEqual(only.latest, 15.0)
        XCTAssertEqual(only.latestDate, latest)
    }

    // MARK: Ordering by most-recent series first

    func testSeriesAreOrderedByMostRecentLatestDateDescending() throws {
        let oldest = try date(year: 2025, month: 1, day: 1)
        let middle = try date(year: 2025, month: 4, day: 1)
        let newest = try date(year: 2025, month: 7, day: 1)

        let a = LabResult(catalogID: "hemoglobin", value: 14.0, unit: "g/dL", date: oldest)
        let b = LabResult(catalogID: "ldlCholesterol", value: 90.0, unit: "mg/dL", date: newest)
        let c = LabResult(catalogID: "totalCholesterol", value: 180.0, unit: "mg/dL", date: middle)
        attach(a, in: "Panel A", date: oldest)
        attach(b, in: "Panel B", date: newest)
        attach(c, in: "Panel C", date: middle)
        try context.save()

        let series = BiomarkerGrouping.series(from: [a, b, c])

        XCTAssertEqual(series.map(\.id), ["ldlcholesterol", "totalcholesterol", "hemoglobin"])
    }

    // MARK: Cap at 12 series

    func testSeriesListIsCappedAtTwelveKeepingTheMostRecent() throws {
        var allResults: [LabResult] = []
        // 13 distinct synthetic tests, each with a single result on an
        // increasing date: marker0 is oldest, marker12 is newest.
        for index in 0..<13 {
            let day = try date(year: 2025, month: 1, day: 1 + index)
            let result = LabResult(catalogID: "marker\(index)", value: Double(index), unit: "u", date: day)
            attach(result, in: "Panel \(index)", date: day)
            allResults.append(result)
        }
        try context.save()

        let series = BiomarkerGrouping.series(from: allResults)

        XCTAssertEqual(series.count, BiomarkerGrouping.seriesCap)
        XCTAssertEqual(series.count, 12)
        // The oldest (marker0) should have been dropped; the 12 most recent remain.
        XCTAssertFalse(series.contains { $0.id == "marker0" })
        XCTAssertEqual(series.first?.id, "marker12")
        XCTAssertEqual(series.last?.id, "marker1")
    }
}
