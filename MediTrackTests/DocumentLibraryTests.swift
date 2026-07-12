import XCTest
import SwiftData
@testable import MediTrack

/// Coverage for `DocumentLibrary.items(from:)` and `DocumentLibrary.filter(_:query:category:)`
/// — the pure, testable flattening/filtering logic behind `DocumentsView`.
/// Mirrors the `HealthTimelineTests` pattern: fixed dates built from
/// `DateComponents`, an in-memory `ModelContainer` retained for the test's
/// lifetime, and no force-unwraps besides `XCTUnwrap`.
@MainActor
final class DocumentLibraryTests: XCTestCase {

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

    @discardableResult
    private func makeReport(
        title: String,
        category: ReportCategory,
        date: Date,
        attachments: [(filename: String, kind: AttachmentKind)]
    ) -> MedicalReport {
        let report = MedicalReport(title: title, category: category, date: date)
        context.insert(report)
        for spec in attachments {
            report.attachments.append(ReportAttachment(filename: spec.filename, kind: spec.kind, data: Data()))
        }
        return report
    }

    // MARK: Flattening

    func testItemsFlattenAllAttachmentsAcrossReports() throws {
        let earlier = try date(year: 2025, month: 1, day: 10)
        let later = try date(year: 2025, month: 6, day: 1)
        let reportA = makeReport(title: "Panel A", category: .labReport, date: earlier, attachments: [
            (filename: "scan.jpg", kind: .image),
        ])
        let reportB = makeReport(title: "Panel B", category: .imaging, date: later, attachments: [
            (filename: "xray.pdf", kind: .pdf),
            (filename: "notes.jpg", kind: .image),
        ])
        try context.save()

        let items = DocumentLibrary.items(from: [reportA, reportB])

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.filename)), Set(["scan.jpg", "xray.pdf", "notes.jpg"]))
        XCTAssertTrue(items.allSatisfy { $0.reportTitle == "Panel A" || $0.reportTitle == "Panel B" })
    }

    func testItemsFromEmptyReportsIsEmpty() {
        XCTAssertTrue(DocumentLibrary.items(from: []).isEmpty)
    }

    func testReportWithNoAttachmentsContributesNoItems() throws {
        let report = MedicalReport(title: "Empty Report", category: .other, date: try date(year: 2025, month: 2, day: 2))
        context.insert(report)
        try context.save()

        XCTAssertTrue(DocumentLibrary.items(from: [report]).isEmpty)
    }

    // MARK: Ordering

    func testItemsOrderedNewestReportFirst() throws {
        let earlier = try date(year: 2025, month: 1, day: 10)
        let later = try date(year: 2025, month: 6, day: 1)
        let reportA = makeReport(title: "Panel A", category: .labReport, date: earlier, attachments: [
            (filename: "old.jpg", kind: .image),
        ])
        let reportB = makeReport(title: "Panel B", category: .imaging, date: later, attachments: [
            (filename: "new.pdf", kind: .pdf),
        ])
        try context.save()

        let items = DocumentLibrary.items(from: [reportA, reportB])

        XCTAssertEqual(items.map(\.filename), ["new.pdf", "old.jpg"])
    }

    func testItemsBreakReportDateTiesByFilename() throws {
        let sameDate = try date(year: 2025, month: 3, day: 1)
        let reportA = makeReport(title: "Same Day A", category: .labReport, date: sameDate, attachments: [
            (filename: "zeta.jpg", kind: .image),
        ])
        let reportB = makeReport(title: "Same Day B", category: .consultation, date: sameDate, attachments: [
            (filename: "alpha.pdf", kind: .pdf),
        ])
        try context.save()

        let items = DocumentLibrary.items(from: [reportA, reportB])

        XCTAssertEqual(items.map(\.filename), ["alpha.pdf", "zeta.jpg"])
    }

    func testItemsWithinSameReportAreOrderedByFilename() throws {
        let sameDate = try date(year: 2025, month: 4, day: 4)
        let report = makeReport(title: "Multi", category: .labReport, date: sameDate, attachments: [
            (filename: "z-last.jpg", kind: .image),
            (filename: "a-first.pdf", kind: .pdf),
            (filename: "m-middle.jpg", kind: .image),
        ])
        try context.save()

        let items = DocumentLibrary.items(from: [report])

        XCTAssertEqual(items.map(\.filename), ["a-first.pdf", "m-middle.jpg", "z-last.jpg"])
    }

    // MARK: Filtering — query

    func testFilterQueryMatchesFilenameCaseInsensitively() throws {
        let report = makeReport(
            title: "Annual Blood Panel",
            category: .labReport,
            date: try date(year: 2025, month: 3, day: 12),
            attachments: [(filename: "LabScan.jpg", kind: .image)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [report])

        let result = DocumentLibrary.filter(items, query: "labscan", category: nil)

        XCTAssertEqual(result.map(\.filename), ["LabScan.jpg"])
    }

    func testFilterQueryMatchesReportTitleCaseInsensitively() throws {
        let report = makeReport(
            title: "Annual Blood Panel",
            category: .labReport,
            date: try date(year: 2025, month: 3, day: 12),
            attachments: [(filename: "scan.jpg", kind: .image)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [report])

        let result = DocumentLibrary.filter(items, query: "BLOOD", category: nil)

        XCTAssertEqual(result.map(\.reportTitle), ["Annual Blood Panel"])
    }

    func testFilterQueryWithNoMatchesReturnsEmpty() throws {
        let report = makeReport(
            title: "Panel",
            category: .labReport,
            date: try date(year: 2025, month: 3, day: 12),
            attachments: [(filename: "a.jpg", kind: .image)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [report])

        XCTAssertTrue(DocumentLibrary.filter(items, query: "nonexistent", category: nil).isEmpty)
    }

    func testFilterEmptyQueryMatchesAll() throws {
        let report = makeReport(
            title: "Panel",
            category: .labReport,
            date: try date(year: 2025, month: 3, day: 12),
            attachments: [(filename: "a.jpg", kind: .image), (filename: "b.pdf", kind: .pdf)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [report])

        XCTAssertEqual(DocumentLibrary.filter(items, query: "", category: nil).count, 2)
    }

    func testFilterWhitespaceOnlyQueryMatchesAll() throws {
        let report = makeReport(
            title: "Panel",
            category: .labReport,
            date: try date(year: 2025, month: 3, day: 12),
            attachments: [(filename: "a.jpg", kind: .image), (filename: "b.pdf", kind: .pdf)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [report])

        XCTAssertEqual(DocumentLibrary.filter(items, query: "   ", category: nil).count, 2)
    }

    // MARK: Filtering — category

    func testFilterByCategoryOnlyReturnsMatchingCategory() throws {
        let labReport = makeReport(
            title: "Lab Panel",
            category: .labReport,
            date: try date(year: 2025, month: 1, day: 1),
            attachments: [(filename: "lab.jpg", kind: .image)]
        )
        let imagingReport = makeReport(
            title: "Chest Scan",
            category: .imaging,
            date: try date(year: 2025, month: 2, day: 1),
            attachments: [(filename: "chest.pdf", kind: .pdf)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [labReport, imagingReport])

        let result = DocumentLibrary.filter(items, query: "", category: .imaging)

        XCTAssertEqual(result.map(\.filename), ["chest.pdf"])
    }

    func testFilterNilCategoryMatchesAllCategories() throws {
        let labReport = makeReport(
            title: "Lab Panel",
            category: .labReport,
            date: try date(year: 2025, month: 1, day: 1),
            attachments: [(filename: "lab.jpg", kind: .image)]
        )
        let imagingReport = makeReport(
            title: "Chest Scan",
            category: .imaging,
            date: try date(year: 2025, month: 2, day: 1),
            attachments: [(filename: "chest.pdf", kind: .pdf)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [labReport, imagingReport])

        XCTAssertEqual(DocumentLibrary.filter(items, query: "", category: nil).count, 2)
    }

    // MARK: Filtering — combined

    func testFilterCombinesQueryAndCategory() throws {
        let labReport = makeReport(
            title: "Lab Panel",
            category: .labReport,
            date: try date(year: 2025, month: 1, day: 1),
            attachments: [(filename: "results.jpg", kind: .image)]
        )
        let imagingReport = makeReport(
            title: "Imaging Results",
            category: .imaging,
            date: try date(year: 2025, month: 2, day: 1),
            attachments: [(filename: "results.pdf", kind: .pdf)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [labReport, imagingReport])

        let result = DocumentLibrary.filter(items, query: "results", category: .imaging)

        XCTAssertEqual(result.map(\.filename), ["results.pdf"])
    }

    func testFilterCombinedQueryAndCategoryWithNoMatchesReturnsEmpty() throws {
        let labReport = makeReport(
            title: "Lab Panel",
            category: .labReport,
            date: try date(year: 2025, month: 1, day: 1),
            attachments: [(filename: "results.jpg", kind: .image)]
        )
        try context.save()
        let items = DocumentLibrary.items(from: [labReport])

        let result = DocumentLibrary.filter(items, query: "results", category: .imaging)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Empty input

    func testFilterOnEmptyItemsReturnsEmpty() {
        XCTAssertTrue(DocumentLibrary.filter([], query: "anything", category: nil).isEmpty)
    }
}
