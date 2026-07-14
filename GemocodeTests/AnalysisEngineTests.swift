import XCTest
import SwiftData
@testable import Gemocode

@MainActor
final class AnalysisEngineTests: XCTestCase {

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

    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000) // deterministic reference instant

    // MARK: Healthy profile

    func testHealthyProfileHasHighScoreAndNoAttentionBPFinding() throws {
        let profile = HealthProfile()
        profile.heightCm = 175
        context.insert(profile)

        let vitals: [VitalSample] = [
            VitalSample(type: .bloodPressure, value: 118, secondaryValue: 76, date: fixedNow),
            VitalSample(type: .heartRate, value: 70, date: fixedNow),
            VitalSample(type: .bloodGlucose, value: 90, date: fixedNow),
            VitalSample(type: .oxygenSaturation, value: 98, date: fixedNow),
            VitalSample(type: .temperature, value: 36.8, date: fixedNow),
            VitalSample(type: .respiratoryRate, value: 16, date: fixedNow),
            VitalSample(type: .sleepHours, value: 8, date: fixedNow),
            VitalSample(type: .weight, value: 70, date: fixedNow)
        ]
        vitals.forEach { context.insert($0) }
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: profile,
            reports: [],
            vitals: vitals,
            medications: [],
            now: fixedNow
        )

        XCTAssertEqual(review.score, 100)
        XCTAssertLessThanOrEqual(review.score, 100)
        XCTAssertGreaterThanOrEqual(review.score, 0)

        let bpAttentionFindings = review.findings.filter {
            $0.category == .vitals && $0.severity == .attention && $0.title.localizedCaseInsensitiveContains("blood pressure")
        }
        XCTAssertTrue(bpAttentionFindings.isEmpty)
    }

    // MARK: Hypertensive BP

    func testHypertensiveBloodPressureProducesFinding() throws {
        let vitals = [VitalSample(type: .bloodPressure, value: 165, secondaryValue: 100, date: fixedNow)]
        vitals.forEach { context.insert($0) }
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [],
            vitals: vitals,
            medications: [],
            now: fixedNow
        )

        let bpFinding = review.findings.first { $0.category == .vitals && $0.title.localizedCaseInsensitiveContains("stage 2") }
        XCTAssertNotNil(bpFinding)
        XCTAssertEqual(bpFinding?.severity, .attention)
    }

    // MARK: Medication interaction

    func testActiveWarfarinAndIbuprofenProduceInteractionFinding() throws {
        let warfarin = Medication(name: "Warfarin", startDate: fixedNow.addingTimeInterval(-30 * 86_400))
        let ibuprofen = Medication(name: "Ibuprofen", startDate: fixedNow.addingTimeInterval(-10 * 86_400))
        context.insert(warfarin)
        context.insert(ibuprofen)
        try context.save()

        XCTAssertTrue(warfarin.isActive)
        XCTAssertTrue(ibuprofen.isActive)

        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [],
            vitals: [],
            medications: [warfarin, ibuprofen],
            now: fixedNow
        )

        let interactionFinding = review.findings.first {
            $0.category == .medications && $0.title.localizedCaseInsensitiveContains("major interaction")
        }
        XCTAssertNotNil(interactionFinding)
        XCTAssertEqual(interactionFinding?.severity, .attention)
    }

    // MARK: Score clamping

    func testScoreIsClampedAndNeverNegative() throws {
        let profile = HealthProfile()
        profile.heightCm = 175
        context.insert(profile)

        // Pile up several critical and attention-level vitals so the raw
        // (unclamped) arithmetic would go well below zero.
        let vitals: [VitalSample] = [
            VitalSample(type: .bloodPressure, value: 200, secondaryValue: 130, date: fixedNow), // crisis -> critical
            VitalSample(type: .bloodGlucose, value: 30, date: fixedNow),                          // critical
            VitalSample(type: .oxygenSaturation, value: 80, date: fixedNow),                      // critical
            VitalSample(type: .temperature, value: 40, date: fixedNow),                           // critical
            VitalSample(type: .heartRate, value: 180, date: fixedNow),                            // attention
            VitalSample(type: .respiratoryRate, value: 5, date: fixedNow),                        // attention
            VitalSample(type: .sleepHours, value: 3, date: fixedNow),                             // attention
            VitalSample(type: .weight, value: 140, date: fixedNow)                                // attention (obese BMI)
        ]
        vitals.forEach { context.insert($0) }
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: profile,
            reports: [],
            vitals: vitals,
            medications: [],
            now: fixedNow
        )

        XCTAssertGreaterThanOrEqual(review.score, 0)
        XCTAssertLessThanOrEqual(review.score, 100)

        let criticalCount = review.findings.filter { $0.severity == .critical }.count
        XCTAssertGreaterThanOrEqual(criticalCount, 4)
    }

    func testEmptyReviewHasZeroScoreAndNoData() {
        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [],
            vitals: [],
            medications: [],
            now: fixedNow
        )

        XCTAssertFalse(review.hasData)
        XCTAssertEqual(review.score, 0)
    }
}
