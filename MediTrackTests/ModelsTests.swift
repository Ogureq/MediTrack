import XCTest
import SwiftData
@testable import MediTrack

/// Pure model-logic tests: `HealthGoal.progress`/`isAchieved`, `Medication.isActive`,
/// `VitalType.healthyRange`, and `Double.compactFormatted`. None of these need a
/// `ModelContainer` — the model types can be instantiated standalone and read back
/// without ever being inserted into a context.
final class ModelsTests: XCTestCase {

    // MARK: HealthGoal.progress(latest:)

    func testProgressClampsAtZeroWhenLatestRegressesPastStart() throws {
        // Losing-weight goal: start 90, target 70. Moving the wrong way (to 100)
        // would produce a negative raw fraction, which must clamp to 0.
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 90)
        let progress = try XCTUnwrap(goal.progress(latest: 100))
        XCTAssertEqual(progress, 0, accuracy: 0.0001)
    }

    func testProgressClampsAtOneWhenLatestOvershootsTarget() throws {
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 90)
        let progress = try XCTUnwrap(goal.progress(latest: 60))
        XCTAssertEqual(progress, 1, accuracy: 0.0001)
    }

    func testProgressReturnsMidpointFractionForDecreasingGoal() throws {
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 90)
        let progress = try XCTUnwrap(goal.progress(latest: 80))
        XCTAssertEqual(progress, 0.5, accuracy: 0.0001)
    }

    func testProgressReturnsMidpointFractionForIncreasingGoal() throws {
        // Gaining-sleep goal: start 6h, target 8h.
        let goal = HealthGoal(type: .sleepHours, targetValue: 8, startValue: 6)
        let progress = try XCTUnwrap(goal.progress(latest: 7))
        XCTAssertEqual(progress, 0.5, accuracy: 0.0001)
    }

    func testProgressIsNilWithoutStartValue() {
        let goal = HealthGoal(type: .weight, targetValue: 70)
        XCTAssertNil(goal.progress(latest: 80))
    }

    func testProgressIsNilWithoutLatestValue() {
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 90)
        XCTAssertNil(goal.progress(latest: nil))
    }

    func testProgressIsNilWhenStartEqualsTarget() {
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 70)
        XCTAssertNil(goal.progress(latest: 65))
    }

    // MARK: HealthGoal.isAchieved(latest:)

    func testIsAchievedForDecreasingGoalDirection() {
        // target (70) <= start (90): achieved once latest drops to or below target.
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 90)
        XCTAssertTrue(goal.isAchieved(latest: 65))
        XCTAssertTrue(goal.isAchieved(latest: 70))
        XCTAssertFalse(goal.isAchieved(latest: 75))
    }

    func testIsAchievedForIncreasingGoalDirection() {
        // target (8) > start (6): achieved once latest rises to or above target.
        let goal = HealthGoal(type: .sleepHours, targetValue: 8, startValue: 6)
        XCTAssertTrue(goal.isAchieved(latest: 8.5))
        XCTAssertTrue(goal.isAchieved(latest: 8))
        XCTAssertFalse(goal.isAchieved(latest: 7))
    }

    func testIsAchievedWithoutStartValueRequiresExactMatch() {
        let goal = HealthGoal(type: .weight, targetValue: 70)
        XCTAssertTrue(goal.isAchieved(latest: 70))
        XCTAssertFalse(goal.isAchieved(latest: 70.5))
    }

    func testIsAchievedIsFalseWithoutLatestValue() {
        let goal = HealthGoal(type: .weight, targetValue: 70, startValue: 90)
        XCTAssertFalse(goal.isAchieved(latest: nil))
    }

    // MARK: Medication.isActive

    func testMedicationWithNilEndDateIsAlwaysActive() {
        let medication = Medication(name: "Vitamin D", startDate: .now)
        XCTAssertNil(medication.endDate)
        XCTAssertTrue(medication.isActive)
    }

    func testMedicationWithPastEndDateIsNotActive() {
        let medication = Medication(
            name: "Amoxicillin",
            startDate: .now.addingTimeInterval(-30 * 86_400),
            endDate: .now.addingTimeInterval(-1 * 86_400)
        )
        XCTAssertFalse(medication.isActive)
    }

    func testMedicationWithFutureEndDateIsActive() {
        let medication = Medication(
            name: "Lisinopril",
            startDate: .now.addingTimeInterval(-30 * 86_400),
            endDate: .now.addingTimeInterval(30 * 86_400)
        )
        XCTAssertTrue(medication.isActive)
    }

    // MARK: VitalType.healthyRange

    func testHealthyRangeLowerIsBelowUpperForEveryDefinedCase() {
        for type in VitalType.allCases {
            guard let range = type.healthyRange else { continue }
            XCTAssertLessThan(range.lowerBound, range.upperBound, "healthyRange for \(type) should have lower < upper")
        }
    }

    func testWeightHasNoHealthyRange() {
        // Weight has no single "healthy" band — it's individual and goal-driven.
        XCTAssertNil(VitalType.weight.healthyRange)
    }

    func testEveryOtherVitalTypeHasAHealthyRange() {
        for type in VitalType.allCases where type != .weight {
            XCTAssertNotNil(type.healthyRange, "\(type) is expected to define a healthyRange")
        }
    }

    // MARK: Double.compactFormatted

    /// The formatted output uses the current locale's decimal separator, so
    /// tests build the expected string from that separator rather than
    /// hardcoding "." to stay correct under any host locale.
    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    func testCompactFormattedDropsDecimalPointForIntegerValues() {
        XCTAssertEqual(Double(5).compactFormatted, "5")
        XCTAssertEqual(Double(0).compactFormatted, "0")
        XCTAssertEqual(Double(100).compactFormatted, "100")
    }

    func testCompactFormattedShowsUpToTwoFractionDigitsWithoutTrailingZeros() {
        XCTAssertEqual(Double(5.5).compactFormatted, "5\(decimalSeparator)5")
        XCTAssertEqual(Double(5.10).compactFormatted, "5\(decimalSeparator)1")
    }

    func testCompactFormattedRoundsBeyondTwoFractionDigits() {
        // 5.567 has no exact 2-decimal representation, so it must round to 5.57
        // regardless of rounding-mode edge cases (this isn't a halfway tie).
        XCTAssertEqual(Double(5.567).compactFormatted, "5\(decimalSeparator)57")
    }
}
