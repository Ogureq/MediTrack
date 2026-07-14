import XCTest
import SwiftData
@testable import Gemocode

/// Additional `AnalysisEngine.generateReview` coverage beyond
/// `AnalysisEngineTests`: BMI categories, derived lipid ratios, worsening
/// vital trends, symptom- and appointment-driven findings, and score
/// monotonicity between a healthy and an attention-heavy data set.
@MainActor
final class AnalysisEngineEdgeTests: XCTestCase {

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

    private let fixedNow = Date(timeIntervalSince1970: 1_751_000_000) // deterministic reference instant

    // MARK: BMI category findings

    func testUnderweightBMIProducesAttentionFinding() throws {
        let profile = HealthProfile()
        profile.heightCm = 175
        context.insert(profile)

        let weight = VitalSample(type: .weight, value: 45, date: fixedNow) // BMI ~14.7
        context.insert(weight)
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: profile,
            reports: [],
            vitals: [weight],
            medications: [],
            now: fixedNow
        )

        let bmiFinding = try XCTUnwrap(review.findings.first {
            $0.category == .vitals && $0.title.localizedCaseInsensitiveContains("underweight")
        })
        XCTAssertEqual(bmiFinding.severity, .attention)
    }

    func testObeseBMIProducesAttentionFinding() throws {
        let profile = HealthProfile()
        profile.heightCm = 175
        context.insert(profile)

        let weight = VitalSample(type: .weight, value: 100, date: fixedNow) // BMI ~32.7
        context.insert(weight)
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: profile,
            reports: [],
            vitals: [weight],
            medications: [],
            now: fixedNow
        )

        let bmiFinding = try XCTUnwrap(review.findings.first {
            $0.category == .vitals && $0.title.localizedCaseInsensitiveContains("obese")
        })
        XCTAssertEqual(bmiFinding.severity, .attention)
    }

    // MARK: Derived lipid findings

    func testHighCholesterolRatioAndNonHDLProduceAttentionFindings() throws {
        let report = MedicalReport(title: "Lipid Panel", category: .labReport, date: fixedNow)
        context.insert(report)
        report.labResults.append(LabResult(catalogID: "totalCholesterol", value: 250, unit: "mg/dL", date: fixedNow))
        report.labResults.append(LabResult(catalogID: "hdlCholesterol", value: 40, unit: "mg/dL", date: fixedNow))
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [report],
            vitals: [],
            medications: [],
            now: fixedNow
        )

        let ratioFinding = try XCTUnwrap(review.findings.first {
            $0.category == .labs && $0.title.localizedCaseInsensitiveContains("cholesterol ratio is high")
        })
        XCTAssertEqual(ratioFinding.severity, .attention)

        let nonHDLFinding = try XCTUnwrap(review.findings.first {
            $0.category == .labs && $0.title.localizedCaseInsensitiveContains("non-hdl cholesterol is high")
        })
        XCTAssertEqual(nonHDLFinding.severity, .attention)
    }

    // MARK: Trend finding

    func testWorseningHeartRateTrendProducesAttentionFinding() throws {
        // Three readings moving further outside the 50...100 healthy range.
        let samples = [
            VitalSample(type: .heartRate, value: 90, date: fixedNow.addingTimeInterval(-20 * 86_400)),
            VitalSample(type: .heartRate, value: 110, date: fixedNow.addingTimeInterval(-10 * 86_400)),
            VitalSample(type: .heartRate, value: 130, date: fixedNow)
        ]
        samples.forEach { context.insert($0) }
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [],
            vitals: samples,
            medications: [],
            now: fixedNow
        )

        let trendFinding = try XCTUnwrap(review.findings.first {
            $0.category == .trends && $0.title.localizedCaseInsensitiveContains("resting heart rate")
        })
        XCTAssertEqual(trendFinding.severity, .attention)

        let trendInsight = try XCTUnwrap(review.trends.first { $0.metricName == VitalType.heartRate.displayName })
        XCTAssertEqual(trendInsight.direction, .worsening)
    }

    // MARK: Symptom-driven finding

    func testSevereRecentSymptomProducesAttentionFinding() throws {
        let symptom = SymptomEntry(name: "Chest pain", severity: 9, date: fixedNow.addingTimeInterval(-2 * 86_400))
        context.insert(symptom)
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [],
            vitals: [],
            medications: [],
            symptoms: [symptom],
            now: fixedNow
        )

        let symptomFinding = try XCTUnwrap(review.findings.first {
            $0.category == .general && $0.title.localizedCaseInsensitiveContains("severe symptom logged")
        })
        XCTAssertEqual(symptomFinding.severity, .attention)
        XCTAssertTrue(symptomFinding.title.localizedCaseInsensitiveContains("chest pain"))
    }

    // MARK: Appointment finding

    func testUpcomingAppointmentProducesInfoFinding() throws {
        let appointment = Appointment(
            title: "Annual Physical",
            doctor: "Dr. Lee",
            date: fixedNow.addingTimeInterval(5 * 86_400)
        )
        context.insert(appointment)
        try context.save()

        let review = AnalysisEngine.generateReview(
            profile: nil,
            reports: [],
            vitals: [],
            medications: [],
            appointments: [appointment],
            now: fixedNow
        )

        let appointmentFinding = try XCTUnwrap(review.findings.first {
            $0.category == .general && $0.title.localizedCaseInsensitiveContains("upcoming: annual physical")
        })
        XCTAssertEqual(appointmentFinding.severity, .info)
        XCTAssertTrue(appointmentFinding.detail.contains("Dr. Lee"))
    }

    // MARK: Score monotonicity

    func testAttentionHeavyReviewScoresLowerThanHealthyBaseline() throws {
        let healthyProfile = HealthProfile()
        healthyProfile.heightCm = 175
        context.insert(healthyProfile)

        let healthyVitals: [VitalSample] = [
            VitalSample(type: .bloodPressure, value: 118, secondaryValue: 76, date: fixedNow),
            VitalSample(type: .heartRate, value: 70, date: fixedNow),
            VitalSample(type: .bloodGlucose, value: 90, date: fixedNow),
            VitalSample(type: .oxygenSaturation, value: 98, date: fixedNow),
            VitalSample(type: .temperature, value: 36.8, date: fixedNow),
            VitalSample(type: .respiratoryRate, value: 16, date: fixedNow),
            VitalSample(type: .sleepHours, value: 8, date: fixedNow),
            VitalSample(type: .weight, value: 70, date: fixedNow)
        ]
        healthyVitals.forEach { context.insert($0) }

        let unhealthyProfile = HealthProfile()
        unhealthyProfile.heightCm = 175
        context.insert(unhealthyProfile)

        let unhealthyVitals: [VitalSample] = [
            VitalSample(type: .bloodPressure, value: 130, secondaryValue: 85, date: fixedNow), // Stage 1 -> attention
            VitalSample(type: .heartRate, value: 110, date: fixedNow),                          // attention
            VitalSample(type: .sleepHours, value: 5, date: fixedNow),                           // attention
            VitalSample(type: .weight, value: 100, date: fixedNow)                              // obese BMI -> attention
        ]
        unhealthyVitals.forEach { context.insert($0) }
        try context.save()

        let healthyReview = AnalysisEngine.generateReview(
            profile: healthyProfile,
            reports: [],
            vitals: healthyVitals,
            medications: [],
            now: fixedNow
        )

        let unhealthyReview = AnalysisEngine.generateReview(
            profile: unhealthyProfile,
            reports: [],
            vitals: unhealthyVitals,
            medications: [],
            now: fixedNow
        )

        XCTAssertEqual(healthyReview.score, 100)
        XCTAssertLessThan(unhealthyReview.score, healthyReview.score)

        let attentionCount = unhealthyReview.findings.filter { $0.severity == .attention }.count
        XCTAssertGreaterThanOrEqual(attentionCount, 4)
        XCTAssertEqual(unhealthyReview.findings.filter { $0.severity == .critical }.count, 0)
    }
}
