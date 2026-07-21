import XCTest
import SwiftData
@testable import Gemocode

/// Coverage for `RetestSchedule`: the deterministic, on-device "when should
/// I re-test this?" engine. Mirrors the `AnalysisEngineTests` /
/// `HealthTimelineTests` pattern — fixed dates built from `DateComponents`,
/// an in-memory `ModelContainer` retained for the test's lifetime, and no
/// force-unwraps besides `XCTUnwrap`.
@MainActor
final class RetestScheduleTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    /// Deterministic "today" used across most tests: 2025-07-15 (mid-month,
    /// so month-based interval math never clips against a short month like
    /// February when tests add/subtract months around it).
    var fixedNow: Date!

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
        fixedNow = try date(year: 2025, month: 7, day: 15)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        fixedNow = nil
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

    private func makeReport(date: Date, catalogID: String, value: Double = 1, unit: String = "unit") -> MedicalReport {
        let report = MedicalReport(title: "Panel", category: .labReport, date: date)
        context.insert(report)
        report.labResults.append(LabResult(catalogID: catalogID, value: value, unit: unit, date: date))
        return report
    }

    // MARK: - Interval lookup

    func testIntervalLookupForHbA1cIsSixMonths() {
        XCTAssertEqual(RetestSchedule.intervalMonths(for: "hba1c"), 6)
    }

    func testIntervalLookupForLDLCholesterolIsTwelveMonths() {
        XCTAssertEqual(RetestSchedule.intervalMonths(for: "ldlCholesterol"), 12)
    }

    func testIntervalLookupIsCaseInsensitive() {
        XCTAssertEqual(RetestSchedule.intervalMonths(for: "HbA1c"), 6)
        XCTAssertEqual(RetestSchedule.intervalMonths(for: "LDLCHOLESTEROL"), 12)
    }

    func testIntervalLookupReturnsNilForIDsWithoutASensibleCadence() {
        // Situational/inconsistently-recommended markers deliberately have
        // no entry: CRP/ESR, and nutrients normally rechecked only after an
        // abnormal result.
        XCTAssertNil(RetestSchedule.intervalMonths(for: "crp"))
        XCTAssertNil(RetestSchedule.intervalMonths(for: "esr"))
        XCTAssertNil(RetestSchedule.intervalMonths(for: "ferritin"))
        XCTAssertNil(RetestSchedule.intervalMonths(for: "vitaminB12"))
        XCTAssertNil(RetestSchedule.intervalMonths(for: "insulin"))
    }

    func testIntervalLookupReturnsNilForUnknownID() {
        XCTAssertNil(RetestSchedule.intervalMonths(for: "notARealTest"))
    }

    // MARK: - Latest-date-wins across reports

    func testLatestDateAcrossMultipleReportsWinsForTheSameSeries() throws {
        let earlierDate = try date(year: 2024, month: 1, day: 15)
        let laterDate = try date(year: 2025, month: 1, day: 15)
        let reportA = makeReport(date: earlierDate, catalogID: "ldlCholesterol", value: 150)
        let reportB = makeReport(date: laterDate, catalogID: "ldlCholesterol", value: 110)
        try context.save()

        let items = RetestSchedule.items(reports: [reportA, reportB], now: fixedNow)

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(Calendar.current.isDate(item.lastTestedAt, inSameDayAs: laterDate))
    }

    func testLatestDateWinsRegardlessOfReportArrayOrder() throws {
        // Same as above but with the later-dated report listed FIRST, to
        // guard against an implementation that assumes array order implies
        // chronological order.
        let earlierDate = try date(year: 2024, month: 1, day: 15)
        let laterDate = try date(year: 2025, month: 1, day: 15)
        let reportLater = makeReport(date: laterDate, catalogID: "totalCholesterol", value: 200)
        let reportEarlier = makeReport(date: earlierDate, catalogID: "totalCholesterol", value: 240)
        try context.save()

        let items = RetestSchedule.items(reports: [reportLater, reportEarlier], now: fixedNow)

        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(Calendar.current.isDate(item.lastTestedAt, inSameDayAs: laterDate))
    }

    // MARK: - Display name resolves from the catalog

    func testDisplayNameResolvesFromLabCatalog() throws {
        let report = makeReport(date: fixedNow, catalogID: "ldlCholesterol")
        try context.save()

        let item = try XCTUnwrap(RetestSchedule.items(reports: [report], now: fixedNow).first)
        XCTAssertEqual(item.displayName, "LDL Cholesterol")
    }

    // MARK: - Classification boundaries

    func testDueYesterdayIsOverdue() throws {
        let dueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: fixedNow))
        let lastTested = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -6, to: dueDate)) // hba1c: 6 months
        let report = makeReport(date: lastTested, catalogID: "hba1c")
        try context.save()

        let item = try XCTUnwrap(RetestSchedule.items(reports: [report], now: fixedNow).first)
        XCTAssertEqual(item.status, .overdue)
    }

    func testDueInThirtyDaysIsDueSoon() throws {
        let dueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 30, to: fixedNow))
        let lastTested = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -6, to: dueDate))
        let report = makeReport(date: lastTested, catalogID: "hba1c")
        try context.save()

        let item = try XCTUnwrap(RetestSchedule.items(reports: [report], now: fixedNow).first)
        XCTAssertEqual(item.status, .dueSoon)
    }

    func testDueInThirtyOneDaysIsUpcoming() throws {
        let dueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 31, to: fixedNow))
        let lastTested = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -6, to: dueDate))
        let report = makeReport(date: lastTested, catalogID: "hba1c")
        try context.save()

        let item = try XCTUnwrap(RetestSchedule.items(reports: [report], now: fixedNow).first)
        XCTAssertEqual(item.status, .upcoming)
    }

    func testDueTodayIsNotOverdue() throws {
        // "Due yesterday" is overdue; due exactly today should not be —
        // it falls inside the 0...30 day dueSoon window.
        let lastTested = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -6, to: fixedNow))
        let report = makeReport(date: lastTested, catalogID: "hba1c")
        try context.save()

        let item = try XCTUnwrap(RetestSchedule.items(reports: [report], now: fixedNow).first)
        XCTAssertEqual(item.status, .dueSoon)
    }

    // MARK: - Never due: empty input, no catalog id, unlisted catalog id

    func testEmptyReportsProduceNoItems() {
        XCTAssertTrue(RetestSchedule.items(reports: [], now: fixedNow).isEmpty)
    }

    func testCustomNamedLabWithoutCatalogIDNeverAppears() throws {
        let report = MedicalReport(title: "Panel", category: .labReport, date: fixedNow)
        context.insert(report)
        report.labResults.append(LabResult(customName: "My Custom Test", value: 5, unit: "unit", date: fixedNow))
        try context.save()

        XCTAssertTrue(RetestSchedule.items(reports: [report], now: fixedNow).isEmpty)
    }

    func testCatalogIDWithoutASensibleCadenceNeverAppears() throws {
        // CRP has no cadence entry in RetestSchedule by design.
        let report = makeReport(date: fixedNow, catalogID: "crp")
        try context.save()

        XCTAssertTrue(RetestSchedule.items(reports: [report], now: fixedNow).isEmpty)
    }

    // MARK: - Sort order

    func testSortOrderIsOverdueThenDueSoonThenUpcomingWithOldestDueFirstWithinOverdue() throws {
        // Overdue, further in the past (due 2 months ago) — must sort first.
        let overdueOlderLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -14, to: fixedNow))
        // Overdue, more recent (due 1 month ago) — must sort second.
        let overdueNewerLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -13, to: fixedNow))
        // Due soon: due in 15 days.
        let dueSoonDueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 15, to: fixedNow))
        let dueSoonLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -12, to: dueSoonDueDate))
        // Upcoming: due in 1 month.
        let upcomingLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -11, to: fixedNow))

        let report = MedicalReport(title: "Panel", category: .labReport, date: fixedNow)
        context.insert(report)
        report.labResults.append(LabResult(catalogID: "totalCholesterol", value: 200, unit: "mg/dL", date: overdueOlderLast))
        report.labResults.append(LabResult(catalogID: "ldlCholesterol", value: 120, unit: "mg/dL", date: overdueNewerLast))
        report.labResults.append(LabResult(catalogID: "hdlCholesterol", value: 55, unit: "mg/dL", date: dueSoonLast))
        report.labResults.append(LabResult(catalogID: "triglycerides", value: 100, unit: "mg/dL", date: upcomingLast))
        try context.save()

        let items = RetestSchedule.items(reports: [report], now: fixedNow)

        XCTAssertEqual(items.map(\.id), ["totalcholesterol", "ldlcholesterol", "hdlcholesterol", "triglycerides"])
        XCTAssertEqual(items.map(\.status), [.overdue, .overdue, .dueSoon, .upcoming])
    }

    // MARK: - dueOrSoon convenience

    func testDueOrSoonExcludesUpcomingItems() throws {
        let lastTested = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -11, to: fixedNow)) // due in 1 month
        let report = makeReport(date: lastTested, catalogID: "triglycerides")
        try context.save()

        XCTAssertTrue(RetestSchedule.dueOrSoon(reports: [report], now: fixedNow).isEmpty)
    }

    func testDueOrSoonIncludesOverdueAndDueSoon() throws {
        let overdueLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -13, to: fixedNow))
        let dueSoonDueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10, to: fixedNow))
        let dueSoonLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -12, to: dueSoonDueDate))

        let report = MedicalReport(title: "Panel", category: .labReport, date: fixedNow)
        context.insert(report)
        report.labResults.append(LabResult(catalogID: "ldlCholesterol", value: 120, unit: "mg/dL", date: overdueLast))
        report.labResults.append(LabResult(catalogID: "hdlCholesterol", value: 55, unit: "mg/dL", date: dueSoonLast))
        try context.save()

        let dueOrSoon = RetestSchedule.dueOrSoon(reports: [report], now: fixedNow)
        XCTAssertEqual(dueOrSoon.count, 2)
        XCTAssertTrue(dueOrSoon.allSatisfy { $0.status != .upcoming })
    }

    // MARK: - nextUpcoming convenience

    func testNextUpcomingReturnsSoonestUpcomingItem() throws {
        // triglycerides: last tested 11 months ago -> due in 1 month.
        let soonerLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -11, to: fixedNow))
        // vitaminD: last tested 8 months ago -> due in 4 months.
        let laterLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -8, to: fixedNow))

        let report = MedicalReport(title: "Panel", category: .labReport, date: fixedNow)
        context.insert(report)
        report.labResults.append(LabResult(catalogID: "triglycerides", value: 100, unit: "mg/dL", date: soonerLast))
        report.labResults.append(LabResult(catalogID: "vitaminD", value: 30, unit: "ng/mL", date: laterLast))
        try context.save()

        let next = try XCTUnwrap(RetestSchedule.nextUpcoming(reports: [report], now: fixedNow))
        XCTAssertEqual(next.id, "triglycerides")
        XCTAssertEqual(next.status, .upcoming)
    }

    func testNextUpcomingIsNilWhenNoUpcomingItemsExist() {
        XCTAssertNil(RetestSchedule.nextUpcoming(reports: [], now: fixedNow))
    }

    func testNextUpcomingIgnoresOverdueAndDueSoonItems() throws {
        // Overdue by a wide margin — an earlier (more urgent) dueDate than
        // any upcoming item, so a naive "soonest dueDate overall" pick would
        // wrongly choose this one instead of filtering by status first.
        let overdueLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -20, to: fixedNow))
        // Due soon: due in 10 days.
        let dueSoonDueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10, to: fixedNow))
        let dueSoonLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -12, to: dueSoonDueDate))
        // Upcoming: due in 3 months.
        let upcomingLast = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -9, to: fixedNow))

        let report = MedicalReport(title: "Panel", category: .labReport, date: fixedNow)
        context.insert(report)
        report.labResults.append(LabResult(catalogID: "ldlCholesterol", value: 120, unit: "mg/dL", date: overdueLast))
        report.labResults.append(LabResult(catalogID: "hdlCholesterol", value: 55, unit: "mg/dL", date: dueSoonLast))
        report.labResults.append(LabResult(catalogID: "triglycerides", value: 100, unit: "mg/dL", date: upcomingLast))
        try context.save()

        let next = try XCTUnwrap(RetestSchedule.nextUpcoming(reports: [report], now: fixedNow))
        XCTAssertEqual(next.id, "triglycerides")
        XCTAssertEqual(next.status, .upcoming)
    }

    // MARK: - Draw bundling: nextDraw

    /// Builds a `RetestItem` directly (no report/context round-trip needed —
    /// `nextDraw` operates purely on already-built items).
    private func makeItem(id: String, dueDate: Date, status: RetestStatus, intervalMonths: Int = 12) -> RetestItem {
        RetestItem(
            id: id,
            displayName: id,
            lastTestedAt: dueDate,
            intervalMonths: intervalMonths,
            dueDate: dueDate,
            status: status
        )
    }

    func testNextDrawReturnsNilForEmptyItems() {
        XCTAssertNil(RetestSchedule.nextDraw(items: [], now: fixedNow))
    }

    func testNextDrawBundlesOverdueDueSoonAndUpcomingWithinACustomWindow() throws {
        // Anchors on `now` because an overdue item is present. With the
        // default 30-day window an upcoming item (by definition >30 days out
        // from `now`) could never be pulled in, so this test widens the
        // window to demonstrate all three statuses bundling together.
        let overdueDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -5, to: fixedNow))
        let dueSoonDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10, to: fixedNow))
        let upcomingWithinDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 40, to: fixedNow))
        let upcomingOutsideDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 50, to: fixedNow))

        let items = [
            makeItem(id: "hba1c", dueDate: overdueDue, status: .overdue),
            makeItem(id: "tsh", dueDate: dueSoonDue, status: .dueSoon),
            makeItem(id: "vitaminD", dueDate: upcomingWithinDue, status: .upcoming),
            makeItem(id: "freeT3", dueDate: upcomingOutsideDue, status: .upcoming),
        ]

        let bundle = try XCTUnwrap(RetestSchedule.nextDraw(items: items, now: fixedNow, windowDays: 45))

        XCTAssertEqual(Set(bundle.items.map(\.id)), ["hba1c", "tsh", "vitaminD"])
        XCTAssertTrue(Calendar.current.isDate(bundle.date, inSameDayAs: fixedNow))
        XCTAssertEqual(bundle.estimatedSavings, 30) // 3 tests -> 2 avoided draws * $15
    }

    func testNextDrawWindowEdgeTwentyNineDaysIncludedThirtyOneDaysExcluded() throws {
        // No overdue item, so the anchor is the due-soon item's own due
        // date (day +10), not `now`. Upcoming items are then measured
        // against THAT anchor, not `now`.
        let dueSoonDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10, to: fixedNow))
        let within29Due = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10 + 29, to: fixedNow))
        let outside31Due = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 10 + 31, to: fixedNow))

        let items = [
            makeItem(id: "tsh", dueDate: dueSoonDue, status: .dueSoon),
            makeItem(id: "vitaminD", dueDate: within29Due, status: .upcoming),
            makeItem(id: "freeT3", dueDate: outside31Due, status: .upcoming),
        ]

        let bundle = try XCTUnwrap(RetestSchedule.nextDraw(items: items, now: fixedNow))

        XCTAssertEqual(Set(bundle.items.map(\.id)), ["tsh", "vitaminD"])
        XCTAssertTrue(Calendar.current.isDate(bundle.date, inSameDayAs: dueSoonDue))
    }

    func testNextDrawFallsBackToSoonestUpcomingItemWhenNothingIsDueOrSoon() throws {
        let soonestDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 35, to: fixedNow))
        let withinWindowDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 35 + 20, to: fixedNow))
        let outsideWindowDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 35 + 40, to: fixedNow))

        let items = [
            makeItem(id: "vitaminD", dueDate: soonestDue, status: .upcoming),
            makeItem(id: "tsh", dueDate: withinWindowDue, status: .upcoming),
            makeItem(id: "freeT3", dueDate: outsideWindowDue, status: .upcoming),
        ]

        let bundle = try XCTUnwrap(RetestSchedule.nextDraw(items: items, now: fixedNow))

        XCTAssertEqual(bundle.items.map(\.id), ["vitaminD", "tsh"])
        XCTAssertTrue(Calendar.current.isDate(bundle.date, inSameDayAs: soonestDue))
        XCTAssertEqual(bundle.estimatedSavings, 15) // 2 tests -> 1 avoided draw * $15
    }

    func testNextDrawRequiresFastingWhenAnyBundledTestRequiresFasting() throws {
        let overdueDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: fixedNow))
        let dueSoonDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: fixedNow))

        let fastingItems = [
            makeItem(id: "tsh", dueDate: overdueDue, status: .overdue),        // not fasting
            makeItem(id: "fastingGlucose", dueDate: dueSoonDue, status: .dueSoon), // fasting
        ]
        let fastingBundle = try XCTUnwrap(RetestSchedule.nextDraw(items: fastingItems, now: fixedNow))
        XCTAssertTrue(fastingBundle.requiresFasting)

        let nonFastingItems = [
            makeItem(id: "tsh", dueDate: overdueDue, status: .overdue),
            makeItem(id: "hba1c", dueDate: dueSoonDue, status: .dueSoon),
        ]
        let nonFastingBundle = try XCTUnwrap(RetestSchedule.nextDraw(items: nonFastingItems, now: fixedNow))
        XCTAssertFalse(nonFastingBundle.requiresFasting)
    }

    // MARK: - Savings math

    func testEstimatedSavingsForOneTestBundleIsNil() {
        XCTAssertNil(RetestSchedule.estimatedSavings(forBundleOf: 1))
        XCTAssertNil(RetestSchedule.estimatedSavings(forBundleOf: 0))
    }

    func testEstimatedSavingsForTwoTestBundleIsOneAvoidedDrawFee() {
        XCTAssertEqual(RetestSchedule.estimatedSavings(forBundleOf: 2), RetestSchedule.drawFeePerVisit)
    }

    func testEstimatedSavingsForThreeTestBundleIsTwoAvoidedDrawFees() {
        XCTAssertEqual(RetestSchedule.estimatedSavings(forBundleOf: 3), RetestSchedule.drawFeePerVisit * 2)
    }

    // MARK: - Estimated pricing

    func testEstimatedPriceKnownIDsReturnConservativeFigures() {
        XCTAssertEqual(RetestSchedule.estimatedPrice(for: "hba1c"), 15)
        XCTAssertEqual(RetestSchedule.estimatedPrice(for: "vitaminD"), 40)
        XCTAssertEqual(RetestSchedule.estimatedPrice(for: "HBA1C"), 15) // case-insensitive
    }

    func testEstimatedPriceReturnsNilForIDsOutsideTheIntervalCatalog() {
        // CRP has no re-test cadence and no price entry, by design.
        XCTAssertNil(RetestSchedule.estimatedPrice(for: "crp"))
        XCTAssertNil(RetestSchedule.estimatedPrice(for: "notARealTest"))
    }

    // MARK: - Early-testing waste

    func testEstimatedEarlyTestingWasteOnlyAppliesToUpcomingItems() throws {
        let upcomingDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 60, to: fixedNow))
        let dueSoonDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: fixedNow))
        let overdueDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -5, to: fixedNow))

        let upcomingItem = makeItem(id: "vitaminD", dueDate: upcomingDue, status: .upcoming)
        let dueSoonItem = makeItem(id: "vitaminD", dueDate: dueSoonDue, status: .dueSoon)
        let overdueItem = makeItem(id: "vitaminD", dueDate: overdueDue, status: .overdue)

        XCTAssertEqual(RetestSchedule.estimatedEarlyTestingWaste(for: upcomingItem, now: fixedNow), 40)
        XCTAssertNil(RetestSchedule.estimatedEarlyTestingWaste(for: dueSoonItem, now: fixedNow))
        XCTAssertNil(RetestSchedule.estimatedEarlyTestingWaste(for: overdueItem, now: fixedNow))
    }

    func testEstimatedEarlyTestingWasteIsNilWhenTestHasNoPriceEntry() throws {
        let upcomingDue = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 60, to: fixedNow))
        let unpricedUpcomingItem = makeItem(id: "notARealTest", dueDate: upcomingDue, status: .upcoming)

        XCTAssertNil(RetestSchedule.estimatedEarlyTestingWaste(for: unpricedUpcomingItem, now: fixedNow))
    }

    // MARK: - Fasting flag (LabCatalog)

    func testFastingFlagIsSetForFastingSensitiveTests() {
        for id in ["fastingGlucose", "totalCholesterol", "ldlCholesterol", "hdlCholesterol", "triglycerides", "insulin", "ferritin", "iron", "tibc"] {
            XCTAssertEqual(LabCatalog.reference(for: id)?.requiresFasting, true, "\(id) should require fasting")
        }
    }

    func testFastingFlagDefaultsFalseForNonFastingTests() {
        for id in ["hba1c", "tsh", "hemoglobin", "crp", "vitaminD"] {
            XCTAssertEqual(LabCatalog.reference(for: id)?.requiresFasting, false, "\(id) should not require fasting")
        }
    }

    // MARK: - Tracked test count

    func testTrackedTestCountMatchesIntervalCatalogAndDiffersFromLabCatalogCount() {
        XCTAssertEqual(RetestSchedule.trackedTestCount, RetestSchedule.intervalMonthsByCatalogID.count)
        XCTAssertEqual(RetestSchedule.trackedTestCount, 38)
        XCTAssertEqual(LabCatalog.count, 46)
        XCTAssertLessThan(RetestSchedule.trackedTestCount, LabCatalog.count)
    }
}
