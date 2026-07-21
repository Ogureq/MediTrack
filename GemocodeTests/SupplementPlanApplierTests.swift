import XCTest
import SwiftData
@testable import Gemocode

/// Tests for `SupplementPlanApplier` — the shared helper extracted from
/// `ActionPlanView`'s original "Add Plan + Set Reminders" logic so
/// `ScanReportView`'s automatic post-save supplement add can reuse the exact
/// same create/skip/reminder rule. In-memory `ModelContainer`, following the
/// same pattern `AnalysisEngineTests` uses. `schedule`/`cancelReminder`
/// closures never touch `UNUserNotificationCenter` in these tests — they
/// just record what they were called with, since `SupplementPlanApplier`
/// itself never imports `NotificationService` (callers own scheduling).
@MainActor
final class SupplementPlanApplierTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Medication.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)

    private func makePlanItem(
        form: SupplementForm,
        labTestID: String,
        doseLow: Double = 1000,
        doseHigh: Double = 2000,
        doseUnit: SupplementDoseUnit = .iu,
        frequency: SupplementFrequency = .daily,
        timing: SupplementTiming = .withFattyMeal
    ) -> PlanItem {
        PlanItem(
            labTestID: labTestID,
            currentValue: 15,
            unit: "ng/mL",
            range: 30...100,
            status: .low,
            supplementForm: form,
            doseLow: doseLow,
            doseHigh: doseHigh,
            doseUnit: doseUnit,
            frequency: frequency,
            timing: timing,
            suggestedRetestDate: fixedNow
        )
    }

    // MARK: - Creates

    func testApplyCreatesOneMedicationPerItem() throws {
        let items = [
            makePlanItem(form: .vitaminD3, labTestID: "vitamind"),
            makePlanItem(form: .magnesium, labTestID: "magnesium", doseLow: 200, doseHigh: 400, doseUnit: .mg, timing: .none),
        ]
        var scheduledCount = 0
        let created = SupplementPlanApplier.apply(items: items, context: context) { _ in
            scheduledCount += 1
        }

        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(scheduledCount, 2, "schedule(_:) must be called exactly once per newly created medication")

        let saved = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(saved.allSatisfy(\.reminderEnabled), "every auto-added supplement gets a reminder enabled")
        XCTAssertTrue(saved.allSatisfy { $0.reminderTime != nil })
    }

    func testCreatedMedicationUsesDoseMidpointNotRange() throws {
        // Iron bisglycinate: doseLow 18, doseHigh 27 -> midpoint 22.5.
        let item = makePlanItem(form: .ironBisglycinate, labTestID: "ferritin", doseLow: 18, doseHigh: 27, doseUnit: .mg, frequency: .everyOtherDay, timing: .emptyStomachWithVitaminC)
        let created = SupplementPlanApplier.apply(items: [item], context: context) { _ in }

        let medication = try XCTUnwrap(created.first)
        XCTAssertEqual(medication.dosage, "22.5 mg", "dosage text should be the dose midpoint, not the label range")
        XCTAssertTrue(medication.frequency.contains("empty stomach"), "timing note should be folded into the frequency text")
    }

    func testCreatedMedicationNameMatchesSupplementForm() throws {
        let item = makePlanItem(form: .folate, labTestID: "folate", doseLow: 400, doseHigh: 800, doseUnit: .mcg, timing: .none)
        let created = SupplementPlanApplier.apply(items: [item], context: context) { _ in }
        XCTAssertEqual(created.first?.name, SupplementPlanApplier.supplementName(.folate))
    }

    // MARK: - Skips existing

    func testApplySkipsSupplementAlreadyPresentByName() throws {
        let existing = Medication(name: "Vitamin D3", dosage: "1000 IU", frequency: "daily")
        context.insert(existing)
        try context.save()

        let items = [makePlanItem(form: .vitaminD3, labTestID: "vitamind")]
        let created = SupplementPlanApplier.apply(items: items, context: context) { _ in
            XCTFail("schedule(_:) must not be called for a skipped supplement")
        }

        XCTAssertTrue(created.isEmpty, "an already-present supplement must be skipped, not duplicated")
        let saved = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(saved.count, 1, "no duplicate row should be created")
    }

    func testApplySkipMatchIsCaseInsensitive() throws {
        let existing = Medication(name: "vitamin d3", dosage: "", frequency: "")
        context.insert(existing)
        try context.save()

        let items = [makePlanItem(form: .vitaminD3, labTestID: "vitamind")]
        let created = SupplementPlanApplier.apply(items: items, context: context) { _ in }
        XCTAssertTrue(created.isEmpty)
    }

    func testApplyDoesNotDuplicateWithinSameBatch() throws {
        // Two items resolving to the same supplement form within a single
        // `apply` call must still yield only one Medication — defensive,
        // since ActionPlan.generate never actually emits two PlanItems for
        // the same form, but the applier itself should not assume that.
        let items = [
            makePlanItem(form: .vitaminD3, labTestID: "vitamind"),
            makePlanItem(form: .vitaminD3, labTestID: "vitamind"),
        ]
        let created = SupplementPlanApplier.apply(items: items, context: context) { _ in }
        XCTAssertEqual(created.count, 1)
    }

    func testApplyWithEmptyItemsCreatesNothing() {
        let created = SupplementPlanApplier.apply(items: [], context: context) { _ in
            XCTFail("schedule(_:) must not be called when there are no items")
        }
        XCTAssertTrue(created.isEmpty)
    }

    // MARK: - Undo round-trip

    func testUndoRemovesCreatedMedications() throws {
        let items = [makePlanItem(form: .folate, labTestID: "folate", doseLow: 400, doseHigh: 800, doseUnit: .mcg, timing: .none)]
        let created = SupplementPlanApplier.apply(items: items, context: context) { _ in }
        XCTAssertEqual(created.count, 1)

        SupplementPlanApplier.unapply(created, context: context)

        let afterUndo = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertTrue(afterUndo.isEmpty, "undo must remove every medication apply created")
    }

    func testUndoThenReapplyCreatesAgainRatherThanSkipping() throws {
        let items = [makePlanItem(form: .magnesium, labTestID: "magnesium", doseLow: 200, doseHigh: 400, doseUnit: .mg, timing: .none)]
        let firstApply = SupplementPlanApplier.apply(items: items, context: context) { _ in }
        XCTAssertEqual(firstApply.count, 1)

        SupplementPlanApplier.unapply(firstApply, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Medication>()).isEmpty)

        // Round trip: re-applying the same plan after undo must create
        // again — proving unapply genuinely deleted the row rather than,
        // say, marking it inactive (which apply's name-match would then
        // still see as "already present").
        let secondApply = SupplementPlanApplier.apply(items: items, context: context) { _ in }
        XCTAssertEqual(secondApply.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).count, 1)
    }

    func testUnapplyOnEmptyListIsANoOp() throws {
        SupplementPlanApplier.unapply([], context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Medication>()).isEmpty)
    }
}
