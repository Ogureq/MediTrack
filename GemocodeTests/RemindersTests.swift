import XCTest
import SwiftData
@testable import Gemocode

/// Coverage for `Reminder`/`ReminderCompletion`: same-day completion lookup
/// (`Reminder.isCompleted(on:)`), the cascade-delete relationship shape via
/// an in-memory `ModelContainer`, and the `BackupService` export/restore
/// round trip now that reminders (and the `HealthProfile` quiz fields) are
/// part of the payload.
@MainActor
final class RemindersTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeInMemoryContainer()
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
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

    // MARK: Reminder.isCompleted(on:)

    func testIsCompletedIsTrueForSameCalendarDay() throws {
        let morning = try date(year: 2025, month: 6, day: 10, hour: 8)
        let lateEveningSameDay = try date(year: 2025, month: 6, day: 10, hour: 21)

        let reminder = Reminder(title: "Take Atorvastatin")
        context.insert(reminder)
        context.insert(ReminderCompletion(date: lateEveningSameDay, reminder: reminder))
        try context.save()

        XCTAssertTrue(reminder.isCompleted(on: morning))
    }

    func testIsCompletedIsFalseForADifferentDay() throws {
        let today = try date(year: 2025, month: 6, day: 10)
        let yesterday = try date(year: 2025, month: 6, day: 9)

        let reminder = Reminder(title: "Take Vitamin D3")
        context.insert(reminder)
        context.insert(ReminderCompletion(date: today, reminder: reminder))
        try context.save()

        XCTAssertFalse(reminder.isCompleted(on: yesterday))
    }

    func testIsCompletedWithTwoCompletionsCoversTodayButNotYesterday() throws {
        let twoDaysAgo = try date(year: 2025, month: 6, day: 8)
        let yesterday = try date(year: 2025, month: 6, day: 9)
        let today = try date(year: 2025, month: 6, day: 10)

        let reminder = Reminder(title: "Take Warfarin")
        context.insert(reminder)
        context.insert(ReminderCompletion(date: twoDaysAgo, reminder: reminder))
        context.insert(ReminderCompletion(date: today, reminder: reminder))
        try context.save()

        XCTAssertTrue(reminder.isCompleted(on: today))
        XCTAssertFalse(reminder.isCompleted(on: yesterday))
    }

    // MARK: Cascade delete shape

    func testDeletingReminderCascadesToItsCompletions() throws {
        let day = try date(year: 2025, month: 6, day: 10)

        let reminder = Reminder(title: "Take Atorvastatin")
        context.insert(reminder)
        context.insert(ReminderCompletion(date: day, reminder: reminder))
        context.insert(ReminderCompletion(date: day, reminder: reminder))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderCompletion>()).count, 2)

        context.delete(reminder)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderCompletion>()).count, 0)
    }

    // MARK: BackupService round trip

    func testExportAndRestoreRoundTripIncludesRemindersAndQuizFields() async throws {
        let sourceContainer = try Self.makeInMemoryContainer()
        let sourceContext = sourceContainer.mainContext
        let destinationContainer = try Self.makeInMemoryContainer()
        let destinationContext = destinationContainer.mainContext

        let completionDate = try date(year: 2025, month: 6, day: 10, hour: 8)
        let timeOfDay = try date(year: 2000, month: 1, day: 1, hour: 8)

        let profile = HealthProfile(
            activityLevel: ActivityLevel.moderate.rawValue,
            typicalSleepHours: 7.5,
            dietStyle: "Mediterranean",
            exerciseDaysPerWeek: 4,
            healthGoalTags: ["Improve sleep", "Lower cholesterol"],
            healthConcerns: ["Family history of heart disease"],
            supplements: ["Vitamin D3"],
            hasCompletedQuiz: true
        )
        profile.name = "Jane Doe"
        sourceContext.insert(profile)

        let reminder = Reminder(
            title: "Take Atorvastatin",
            detail: "With breakfast",
            systemImage: "pills.fill",
            timeOfDay: timeOfDay,
            isAISuggested: true,
            suggestionReason: "Taking statins consistently with food can improve tolerability."
        )
        sourceContext.insert(reminder)
        context.insert(ReminderCompletion(date: completionDate, reminder: reminder))
        try sourceContext.save()

        let data = try await BackupService.export(from: sourceContext, passphrase: "correct horse battery staple")
        let restoredCount = try await BackupService.restore(from: data, passphrase: "correct horse battery staple", into: destinationContext)
        XCTAssertGreaterThan(restoredCount, 0)

        let restoredProfiles = try destinationContext.fetch(FetchDescriptor<HealthProfile>())
        let restoredProfile = try XCTUnwrap(restoredProfiles.first)
        XCTAssertEqual(restoredProfile.name, "Jane Doe")
        XCTAssertEqual(restoredProfile.activityLevel, ActivityLevel.moderate.rawValue)
        XCTAssertEqual(restoredProfile.typicalSleepHours, 7.5)
        XCTAssertEqual(restoredProfile.dietStyle, "Mediterranean")
        XCTAssertEqual(restoredProfile.exerciseDaysPerWeek, 4)
        XCTAssertEqual(restoredProfile.healthGoalTags, ["Improve sleep", "Lower cholesterol"])
        XCTAssertEqual(restoredProfile.healthConcerns, ["Family history of heart disease"])
        XCTAssertEqual(restoredProfile.supplements, ["Vitamin D3"])
        XCTAssertTrue(restoredProfile.hasCompletedQuiz)

        let restoredReminders = try destinationContext.fetch(FetchDescriptor<Reminder>())
        XCTAssertEqual(restoredReminders.count, 1)
        let restoredReminder = try XCTUnwrap(restoredReminders.first)
        XCTAssertEqual(restoredReminder.title, "Take Atorvastatin")
        XCTAssertEqual(restoredReminder.detail, "With breakfast")
        XCTAssertTrue(restoredReminder.isAISuggested)
        XCTAssertEqual(restoredReminder.suggestionReason, "Taking statins consistently with food can improve tolerability.")
        XCTAssertEqual(restoredReminder.completions?.count, 1)
        XCTAssertTrue(restoredReminder.isCompleted(on: completionDate))
    }

    func testBackupPayloadDecodesWhenRemindersKeyIsMissing() throws {
        // Simulates a backup file created before reminders existed: the key
        // is absent entirely. The optional `reminders` property should
        // decode to nil rather than throwing.
        let json = """
        {
            "version": 1,
            "exportedAt": "2023-11-14T22:13:20Z",
            "reports": [],
            "vitals": [],
            "medications": [],
            "symptoms": [],
            "appointments": [],
            "scoreSnapshots": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: Data(json.utf8))
        XCTAssertNil(decoded.reminders)
        XCTAssertNil(decoded.profile)
    }
}
