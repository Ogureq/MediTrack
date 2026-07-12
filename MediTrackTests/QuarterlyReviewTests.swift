import XCTest
import SwiftData
@testable import MediTrack

/// Coverage for `QuarterlyReview`: the deterministic, on-device Quarterly
/// Health Review builder. Mirrors the `AnalysisEngineTests` /
/// `HealthTimelineTests` pattern — fixed dates built from `DateComponents`,
/// an in-memory `ModelContainer` retained for the test's lifetime, and no
/// force-unwraps besides `XCTUnwrap`. UserDefaults keys touched by
/// `markCompleted`/`lastCompleted` are reset in both `setUp` and `tearDown`,
/// following the convention in `AppLockTests`.
@MainActor
final class QuarterlyReviewTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    /// Deterministic "today" used across most tests: 2025-07-12.
    var fixedNow: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: QuarterlyReview.lastCompletedKey)
        fixedNow = try date(year: 2025, month: 7, day: 12)
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
        UserDefaults.standard.removeObject(forKey: QuarterlyReview.lastCompletedKey)
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

    private func emptyBuild(
        snapshots: [ScoreSnapshot] = [],
        vitals: [VitalSample] = [],
        labResults: [LabResult] = [],
        goals: [HealthGoal] = [],
        reminders: [Reminder] = [],
        symptoms: [SymptomEntry] = [],
        now: Date
    ) -> QuarterlyReviewSummary {
        QuarterlyReview.build(
            snapshots: snapshots,
            vitals: vitals,
            labResults: labResults,
            goals: goals,
            reminders: reminders,
            symptoms: symptoms,
            now: now,
            calendar: .current
        )
    }

    // MARK: isDue — no data

    func testIsDueFalseWhenThereIsNoData() {
        XCTAssertFalse(QuarterlyReview.isDue(lastCompleted: nil, earliestData: nil, now: fixedNow, calendar: .current))
    }

    // MARK: isDue — insufficient data span

    func testIsDueFalseWhenLessThanFourteenDaysOfData() throws {
        let earliestData = try date(year: 2025, month: 7, day: 5) // 7 days of data
        XCTAssertFalse(QuarterlyReview.isDue(lastCompleted: nil, earliestData: earliestData, now: fixedNow, calendar: .current))
    }

    // MARK: isDue — never completed

    func testIsDueTrueWhenNeverCompletedAndEnoughDataExists() throws {
        let earliestData = try date(year: 2025, month: 6, day: 1) // 41 days of data
        XCTAssertTrue(QuarterlyReview.isDue(lastCompleted: nil, earliestData: earliestData, now: fixedNow, calendar: .current))
    }

    // MARK: isDue — cadence boundary

    func testIsDueFalseWhenCompletedEightyNineDaysAgo() throws {
        let earliestData = try date(year: 2024, month: 1, day: 1)
        let lastCompleted = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -89, to: fixedNow))
        XCTAssertFalse(QuarterlyReview.isDue(lastCompleted: lastCompleted, earliestData: earliestData, now: fixedNow, calendar: .current))
    }

    func testIsDueTrueWhenCompletedNinetyOneDaysAgo() throws {
        let earliestData = try date(year: 2024, month: 1, day: 1)
        let lastCompleted = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -91, to: fixedNow))
        XCTAssertTrue(QuarterlyReview.isDue(lastCompleted: lastCompleted, earliestData: earliestData, now: fixedNow, calendar: .current))
    }

    // MARK: build — window filtering (score snapshots)

    func testBuildExcludesScoreSnapshotsOlderThanNinetyDaysAndDeltaIsNilWithOneInWindow() throws {
        let oldDate = try date(year: 2025, month: 3, day: 1) // well over 90 days before fixedNow
        let recentDate = try date(year: 2025, month: 6, day: 1) // within the last 90 days
        let oldSnapshot = ScoreSnapshot(date: oldDate, score: 40)
        let recentSnapshot = ScoreSnapshot(date: recentDate, score: 70)
        context.insert(oldSnapshot)
        context.insert(recentSnapshot)
        try context.save()

        let summary = emptyBuild(snapshots: [oldSnapshot, recentSnapshot], now: fixedNow)

        XCTAssertEqual(summary.startScore, 70)
        XCTAssertEqual(summary.endScore, 70)
        XCTAssertNil(summary.scoreDelta, "Delta must be nil with only a single snapshot inside the window")
    }

    // MARK: build — scoreDelta math with two in-window snapshots

    func testBuildComputesScoreDeltaWithTwoSnapshotsInWindow() throws {
        let earlierDate = try date(year: 2025, month: 5, day: 15)
        let laterDate = try date(year: 2025, month: 7, day: 1)
        let earlier = ScoreSnapshot(date: earlierDate, score: 50)
        let later = ScoreSnapshot(date: laterDate, score: 65)
        context.insert(earlier)
        context.insert(later)
        try context.save()

        let summary = emptyBuild(snapshots: [earlier, later], now: fixedNow)

        XCTAssertEqual(summary.startScore, 50)
        XCTAssertEqual(summary.endScore, 65)
        XCTAssertEqual(summary.scoreDelta, 15)
    }

    // MARK: build — window filtering (vitals)

    func testBuildExcludesVitalSamplesOlderThanNinetyDaysFromChangeCalculation() throws {
        let oldDate = try date(year: 2025, month: 3, day: 1) // outside the window
        let recentDate = try date(year: 2025, month: 6, day: 15) // inside the window
        let oldSample = VitalSample(type: .weight, value: 90, date: oldDate)
        let recentSample = VitalSample(type: .weight, value: 85, date: recentDate)
        context.insert(oldSample)
        context.insert(recentSample)
        try context.save()

        // Only one sample falls inside the window, so no VitalChange should
        // be produced (≥2 in-window samples are required).
        let summary = emptyBuild(vitals: [oldSample, recentSample], now: fixedNow)

        XCTAssertTrue(summary.vitalChanges.isEmpty)
    }

    // MARK: direction semantics — blood pressure down = improved

    func testBloodPressureDecreaseIsImproved() throws {
        let earlierDate = try date(year: 2025, month: 5, day: 1)
        let laterDate = try date(year: 2025, month: 7, day: 1)
        let earlier = VitalSample(type: .bloodPressure, value: 145, secondaryValue: 92, date: earlierDate)
        let later = VitalSample(type: .bloodPressure, value: 122, secondaryValue: 80, date: laterDate)
        context.insert(earlier)
        context.insert(later)
        try context.save()

        let summary = emptyBuild(vitals: [earlier, later], now: fixedNow)

        let change = try XCTUnwrap(summary.vitalChanges.first { $0.type == .bloodPressure })
        XCTAssertEqual(change.firstValue, 145)
        XCTAssertEqual(change.lastValue, 122)
        XCTAssertEqual(change.direction, .improved)
    }

    // MARK: direction semantics — HDL down = worsened

    func testHDLCholesterolDecreaseIsWorsened() throws {
        let earlierDate = try date(year: 2025, month: 4, day: 1) // before the window; acts as baseline
        let laterDate = try date(year: 2025, month: 7, day: 1) // inside the window
        let report1 = MedicalReport(title: "Panel A", category: .labReport, date: earlierDate)
        let report2 = MedicalReport(title: "Panel B", category: .labReport, date: laterDate)
        context.insert(report1)
        context.insert(report2)
        let baseline = LabResult(catalogID: "hdlCholesterol", value: 55, unit: "mg/dL", date: earlierDate)
        let latest = LabResult(catalogID: "hdlCholesterol", value: 40, unit: "mg/dL", date: laterDate)
        report1.labResults.append(baseline)
        report2.labResults.append(latest)
        try context.save()

        let summary = emptyBuild(labResults: [baseline, latest], now: fixedNow)

        let change = try XCTUnwrap(summary.labChanges.first { $0.name.localizedCaseInsensitiveContains("HDL") })
        XCTAssertEqual(change.previousValue, 55)
        XCTAssertEqual(change.latestValue, 40)
        XCTAssertEqual(change.direction, .worsened)
    }

    // MARK: direction semantics — LDL down = improved

    func testLDLCholesterolDecreaseIsImproved() throws {
        let earlierDate = try date(year: 2025, month: 4, day: 1)
        let laterDate = try date(year: 2025, month: 7, day: 1)
        let report1 = MedicalReport(title: "Panel A", category: .labReport, date: earlierDate)
        let report2 = MedicalReport(title: "Panel B", category: .labReport, date: laterDate)
        context.insert(report1)
        context.insert(report2)
        let baseline = LabResult(catalogID: "ldlCholesterol", value: 160, unit: "mg/dL", date: earlierDate)
        let latest = LabResult(catalogID: "ldlCholesterol", value: 110, unit: "mg/dL", date: laterDate)
        report1.labResults.append(baseline)
        report2.labResults.append(latest)
        try context.save()

        let summary = emptyBuild(labResults: [baseline, latest], now: fixedNow)

        let change = try XCTUnwrap(summary.labChanges.first { $0.name.localizedCaseInsensitiveContains("LDL") })
        XCTAssertEqual(change.direction, .improved)
    }

    // MARK: direction semantics — weight is always neutral

    func testWeightChangeIsAlwaysSteadyRegardlessOfDirection() throws {
        let earlierDate = try date(year: 2025, month: 5, day: 1)
        let laterDate = try date(year: 2025, month: 7, day: 1)
        let earlier = VitalSample(type: .weight, value: 90, date: earlierDate)
        let later = VitalSample(type: .weight, value: 78, date: laterDate) // a big drop, still neutral
        context.insert(earlier)
        context.insert(later)
        try context.save()

        let summary = emptyBuild(vitals: [earlier, later], now: fixedNow)

        let change = try XCTUnwrap(summary.vitalChanges.first { $0.type == .weight })
        XCTAssertEqual(change.direction, .steady)
    }

    // MARK: longestStreak — a gap breaks the run

    func testLongestStreakBreaksOnGap() throws {
        let reminder = Reminder(title: "Take medication")
        context.insert(reminder)

        // Run of 3 consecutive days, a one-day gap, then a run of 2.
        let runADates = try [
            date(year: 2025, month: 6, day: 1),
            date(year: 2025, month: 6, day: 2),
            date(year: 2025, month: 6, day: 3),
        ]
        let runBDates = try [
            date(year: 2025, month: 6, day: 5),
            date(year: 2025, month: 6, day: 6),
        ]
        for day in runADates + runBDates {
            context.insert(ReminderCompletion(date: day, reminder: reminder))
        }
        try context.save()

        let summary = emptyBuild(reminders: [reminder], now: fixedNow)

        XCTAssertEqual(summary.longestStreak, 3)
    }

    func testLongestStreakIsZeroWithNoCompletions() throws {
        let reminder = Reminder(title: "Take medication")
        context.insert(reminder)
        try context.save()

        let summary = emptyBuild(reminders: [reminder], now: fixedNow)

        XCTAssertEqual(summary.longestStreak, 0)
    }

    // MARK: doctorQuestions — only from worsened items

    func testDoctorQuestionsOnlyIncludeWorsenedItems() throws {
        // Improving blood pressure: must not produce a question.
        let bpEarlier = try date(year: 2025, month: 5, day: 1)
        let bpLater = try date(year: 2025, month: 7, day: 1)
        let bp1 = VitalSample(type: .bloodPressure, value: 150, secondaryValue: 95, date: bpEarlier)
        let bp2 = VitalSample(type: .bloodPressure, value: 118, secondaryValue: 78, date: bpLater)
        context.insert(bp1)
        context.insert(bp2)

        // Worsening HDL: must produce exactly one question.
        let labEarlier = try date(year: 2025, month: 4, day: 1)
        let labLater = try date(year: 2025, month: 7, day: 1)
        let report1 = MedicalReport(title: "Panel A", category: .labReport, date: labEarlier)
        let report2 = MedicalReport(title: "Panel B", category: .labReport, date: labLater)
        context.insert(report1)
        context.insert(report2)
        let hdlBaseline = LabResult(catalogID: "hdlCholesterol", value: 55, unit: "mg/dL", date: labEarlier)
        let hdlLatest = LabResult(catalogID: "hdlCholesterol", value: 38, unit: "mg/dL", date: labLater)
        report1.labResults.append(hdlBaseline)
        report2.labResults.append(hdlLatest)
        try context.save()

        let summary = emptyBuild(
            vitals: [bp1, bp2],
            labResults: [hdlBaseline, hdlLatest],
            now: fixedNow
        )

        XCTAssertEqual(summary.doctorQuestions.count, 1)
        let question = try XCTUnwrap(summary.doctorQuestions.first)
        XCTAssertTrue(question.localizedCaseInsensitiveContains("HDL"))
        // Phrased as a question to bring to a professional, never a diagnosis.
        XCTAssertTrue(question.localizedCaseInsensitiveContains("ask"))
    }

    func testDoctorQuestionsEmptyWhenNothingWorsened() throws {
        let earlier = try date(year: 2025, month: 5, day: 1)
        let later = try date(year: 2025, month: 7, day: 1)
        let bp1 = VitalSample(type: .bloodPressure, value: 150, secondaryValue: 95, date: earlier)
        let bp2 = VitalSample(type: .bloodPressure, value: 118, secondaryValue: 78, date: later)
        context.insert(bp1)
        context.insert(bp2)
        try context.save()

        let summary = emptyBuild(vitals: [bp1, bp2], now: fixedNow)

        XCTAssertTrue(summary.doctorQuestions.isEmpty)
    }

    // MARK: goalsAchieved — transition into achievement during the window

    func testGoalsAchievedOnlyWhenTransitionHappensInsideWindow() throws {
        let goal = HealthGoal(type: .weight, targetValue: 80, startValue: 95)
        context.insert(goal)

        let beforeWindowDate = try date(year: 2025, month: 3, day: 1) // before the 90-day window; not yet achieved
        let inWindowDate = try date(year: 2025, month: 6, day: 15) // inside the window; achieved
        let beforeSample = VitalSample(type: .weight, value: 88, date: beforeWindowDate)
        let afterSample = VitalSample(type: .weight, value: 79, date: inWindowDate)
        context.insert(beforeSample)
        context.insert(afterSample)
        try context.save()

        let summary = emptyBuild(vitals: [beforeSample, afterSample], goals: [goal], now: fixedNow)

        XCTAssertEqual(summary.goalsAchieved.count, 1)
    }

    // MARK: markCompleted / lastCompleted round trip

    func testMarkCompletedThenLastCompletedRoundTrips() throws {
        XCTAssertNil(QuarterlyReview.lastCompleted(defaults: .standard))

        QuarterlyReview.markCompleted(now: fixedNow, defaults: .standard)

        let stored = QuarterlyReview.lastCompleted(defaults: .standard)
        XCTAssertEqual(stored, fixedNow)
    }
}
