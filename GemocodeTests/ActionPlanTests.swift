import XCTest
import SwiftData
@testable import Gemocode

/// Coverage for `ActionPlan`: the rule-based, deterministic engine behind the
/// premium "Action plan" screen. Mirrors the `AnalysisEngineTests` /
/// `RetestScheduleTests` pattern — fixed dates built from `DateComponents`,
/// an in-memory `ModelContainer` retained for the test's lifetime, and no
/// force-unwraps besides `XCTUnwrap`.
@MainActor
final class ActionPlanTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    /// Deterministic "today", mid-month so month-based retest-date math never
    /// clips against a short month.
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

    // MARK: Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int = 9) throws -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return try XCTUnwrap(Calendar.current.date(from: comps))
    }

    /// Builds and inserts a `MedicalReport` carrying one `LabResult` per
    /// `(catalogID, value, unit)` triple, mirroring `RetestScheduleTests`'s
    /// `makeReport` helper.
    private func makeReport(date: Date, results: [(catalogID: String, value: Double, unit: String)]) -> MedicalReport {
        let report = MedicalReport(title: "Panel", category: .labReport, date: date)
        context.insert(report)
        for result in results {
            report.labResults.append(LabResult(catalogID: result.catalogID, value: result.value, unit: result.unit, date: date))
        }
        return report
    }

    /// Builds the `HealthReview` that feeds `ActionPlan.generate`, so each
    /// test only has to describe its lab results / medications.
    private func review(
        profile: HealthProfile? = nil,
        reports: [MedicalReport] = [],
        medications: [Medication] = []
    ) -> HealthReview {
        AnalysisEngine.generateReview(
            profile: profile,
            reports: reports,
            vitals: [],
            medications: medications,
            now: fixedNow
        )
    }

    // MARK: Healthy profile

    func testHealthyProfileProducesEmptyPlanAndEmptyKeepWatching() throws {
        let profile = HealthProfile()
        profile.heightCm = 175
        context.insert(profile)

        // A normal hemoglobin and a normal (in-range) vitamin D — a
        // whitelisted nutrient that's fine should never produce a plan item.
        let report = makeReport(date: fixedNow, results: [
            (catalogID: "hemoglobin", value: 14, unit: "g/dL"),
            (catalogID: "vitaminD", value: 50, unit: "ng/mL")
        ])
        try context.save()

        let healthReview = review(profile: profile, reports: [report])
        let plan = ActionPlan.generate(review: healthReview, medications: [], now: fixedNow)

        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.keepWatching.isEmpty)
        XCTAssertFalse(plan.interactionCheck.wasChecked)
        XCTAssertTrue(plan.interactionCheck.warnings.isEmpty)
    }

    // MARK: Low vitamin D

    func testLowVitaminDProducesD3PlanItemWithDoseRangeAndRetestDate() throws {
        let report = makeReport(date: fixedNow, results: [
            (catalogID: "vitaminD", value: 15, unit: "ng/mL")
        ])
        try context.save()

        let healthReview = review(reports: [report])
        let plan = ActionPlan.generate(review: healthReview, medications: [], now: fixedNow)

        XCTAssertEqual(plan.items.count, 1)
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.labTestID, "vitamind")
        XCTAssertEqual(item.currentValue, 15)
        XCTAssertEqual(item.status, .low)
        XCTAssertEqual(item.supplementForm, .vitaminD3)
        XCTAssertEqual(item.doseLow, 1000)
        XCTAssertEqual(item.doseHigh, 2000)
        XCTAssertEqual(item.doseUnit, .iu)
        XCTAssertEqual(item.frequency, .daily)
        XCTAssertEqual(item.timing, .withFattyMeal)

        // RetestSchedule defines a real 12-month cadence for vitamin D.
        let expectedRetest = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: 12, to: fixedNow))
        XCTAssertEqual(item.suggestedRetestDate, expectedRetest)

        XCTAssertTrue(plan.keepWatching.isEmpty)
    }

    // MARK: Low ferritin

    func testLowFerritinProducesIronPlanItem() throws {
        let profile = HealthProfile()
        profile.sex = .female
        context.insert(profile)

        let report = makeReport(date: fixedNow, results: [
            (catalogID: "ferritin", value: 5, unit: "ng/mL")
        ])
        try context.save()

        let healthReview = review(profile: profile, reports: [report])
        let plan = ActionPlan.generate(review: healthReview, medications: [], now: fixedNow)

        XCTAssertEqual(plan.items.count, 1)
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.labTestID, "ferritin")
        XCTAssertEqual(item.supplementForm, .ironBisglycinate)
        XCTAssertEqual(item.doseLow, 18)
        XCTAssertEqual(item.doseHigh, 27)
        XCTAssertEqual(item.doseUnit, .mg)
        XCTAssertEqual(item.frequency, .everyOtherDay)
        XCTAssertEqual(item.timing, .emptyStomachWithVitaminC)

        // RetestSchedule has no cadence for ferritin (situational marker,
        // rechecked after an abnormal result) — ActionPlan falls back to a
        // conservative 3-month recheck window.
        let expectedRetest = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: 3, to: fixedNow))
        XCTAssertEqual(item.suggestedRetestDate, expectedRetest)
        XCTAssertNil(RetestSchedule.intervalMonths(for: "ferritin"))
    }

    // MARK: High HbA1c — keep watching only, never a supplement

    func testHighHbA1cProducesKeepWatchingOnlyNoSupplement() throws {
        let report = makeReport(date: fixedNow, results: [
            (catalogID: "hba1c", value: 7.0, unit: "%")
        ])
        try context.save()

        let healthReview = review(reports: [report])
        let plan = ActionPlan.generate(review: healthReview, medications: [], now: fixedNow)

        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertEqual(plan.keepWatching.count, 1)
        let watched = try XCTUnwrap(plan.keepWatching.first)
        XCTAssertEqual(watched.labTestID, "hba1c")
        XCTAssertEqual(watched.status, .high)

        // RetestSchedule's real 6-month HbA1c cadence.
        let expectedRetest = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: 6, to: fixedNow))
        XCTAssertEqual(watched.suggestedRetestDate, expectedRetest)
    }

    // MARK: Interaction check

    /// `MedicationInteractions`'s rule table currently has no entries keyed
    /// to iron, magnesium, vitamin D, B12, or folate tokens (only a dormant
    /// "levothyroxine" synonym with no paired rule — confirmed by reading
    /// the full rule table), so no combination of our five whitelisted
    /// supplements can produce a hit without editing that file, which is out
    /// of scope here. This test instead proves the check plumbing end to
    /// end: a real, pre-existing rule (warfarin + NSAID, already covered by
    /// `MedicationInteractionsTests`) fires in the same pass that recommends
    /// an iron supplement for low ferritin, confirming `ActionPlan` unions
    /// supplement identifiers with active medication names and calls
    /// straight through to `MedicationInteractions.check`.
    func testInteractionCheckSurfacesRealMedicationConflictAlongsideSupplement() throws {
        let warfarin = Medication(name: "Warfarin", startDate: fixedNow.addingTimeInterval(-30 * 86_400))
        let ibuprofen = Medication(name: "Ibuprofen", startDate: fixedNow.addingTimeInterval(-10 * 86_400))
        context.insert(warfarin)
        context.insert(ibuprofen)

        let report = makeReport(date: fixedNow, results: [
            (catalogID: "ferritin", value: 5, unit: "ng/mL")
        ])
        try context.save()

        let medications = [warfarin, ibuprofen]
        let healthReview = review(reports: [report], medications: medications)
        let plan = ActionPlan.generate(review: healthReview, medications: medications, now: fixedNow)

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items.first?.supplementForm, .ironBisglycinate)

        XCTAssertTrue(plan.interactionCheck.wasChecked)
        XCTAssertEqual(plan.interactionCheck.warnings.count, 1)
        let warning = try XCTUnwrap(plan.interactionCheck.warnings.first)
        XCTAssertEqual(warning.severity, .major)
        XCTAssertEqual(warning.drugA, "Warfarin")
        XCTAssertEqual(warning.drugB, "Ibuprofen")
    }

    /// Distinguishes "checked, none found" (there was a supplement to check,
    /// no medications, and no hit came back) from "not checked" (nothing at
    /// all to check).
    func testInteractionCheckDistinguishesCheckedNoneFoundFromNotChecked() throws {
        let report = makeReport(date: fixedNow, results: [
            (catalogID: "vitaminD", value: 15, unit: "ng/mL")
        ])
        try context.save()

        let reviewWithSupplement = review(reports: [report])
        let planChecked = ActionPlan.generate(review: reviewWithSupplement, medications: [], now: fixedNow)
        XCTAssertTrue(planChecked.interactionCheck.wasChecked)
        XCTAssertTrue(planChecked.interactionCheck.warnings.isEmpty)

        let emptyReview = review()
        let planNotChecked = ActionPlan.generate(review: emptyReview, medications: [], now: fixedNow)
        XCTAssertFalse(planNotChecked.interactionCheck.wasChecked)
        XCTAssertTrue(planNotChecked.interactionCheck.warnings.isEmpty)
    }

    // MARK: Determinism

    func testGenerateIsDeterministicForIdenticalInputs() throws {
        let profile = HealthProfile()
        profile.sex = .female
        context.insert(profile)

        let warfarin = Medication(name: "Warfarin", startDate: fixedNow.addingTimeInterval(-30 * 86_400))
        let ibuprofen = Medication(name: "Ibuprofen", startDate: fixedNow.addingTimeInterval(-10 * 86_400))
        context.insert(warfarin)
        context.insert(ibuprofen)

        let report = makeReport(date: fixedNow, results: [
            (catalogID: "vitaminD", value: 15, unit: "ng/mL"),
            (catalogID: "ferritin", value: 5, unit: "ng/mL"),
            (catalogID: "hba1c", value: 7.0, unit: "%")
        ])
        try context.save()

        let medications = [warfarin, ibuprofen]
        let healthReview = review(profile: profile, reports: [report], medications: medications)

        let planA = ActionPlan.generate(review: healthReview, medications: medications, now: fixedNow)
        let planB = ActionPlan.generate(review: healthReview, medications: medications, now: fixedNow)

        XCTAssertEqual(planA.items, planB.items)
        XCTAssertEqual(planA.keepWatching, planB.keepWatching)
        XCTAssertEqual(planA.interactionCheck.wasChecked, planB.interactionCheck.wasChecked)
        XCTAssertEqual(planA.interactionCheck.warnings.map(\.explanation), planB.interactionCheck.warnings.map(\.explanation))
        XCTAssertEqual(planA.generatedAt, planB.generatedAt)
    }
}
