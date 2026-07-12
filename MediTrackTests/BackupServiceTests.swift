import XCTest
import SwiftData
@testable import MediTrack

/// Exercises both the plain `Codable` round trip of `BackupPayload` and the
/// real `BackupService.export`/`restore` API against in-memory SwiftData
/// containers.
@MainActor
final class BackupServiceTests: XCTestCase {

    var sourceContainer: ModelContainer!
    var sourceContext: ModelContext!
    var destinationContainer: ModelContainer!
    var destinationContext: ModelContext!

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000) // whole seconds: survives ISO8601 round trip exactly

    override func setUpWithError() throws {
        try super.setUpWithError()
        sourceContainer = try Self.makeInMemoryContainer()
        sourceContext = sourceContainer.mainContext
        destinationContainer = try Self.makeInMemoryContainer()
        destinationContext = destinationContainer.mainContext
    }

    override func tearDownWithError() throws {
        sourceContext = nil
        sourceContainer = nil
        destinationContext = nil
        destinationContainer = nil
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

    // MARK: BackupPayload Codable round trip

    func testBackupPayloadEncodesAndDecodesRoundTrip() throws {
        var payload = BackupPayload()
        payload.version = 1
        payload.exportedAt = fixedNow
        payload.profile = BackupProfile(
            name: "Jane Doe",
            dateOfBirth: fixedNow,
            sex: BiologicalSex.female.rawValue,
            heightCm: 168,
            bloodType: "O+",
            allergies: "Penicillin",
            conditions: "None"
        )
        payload.reports = [
            BackupReport(
                title: "Annual Bloodwork",
                category: ReportCategory.labReport.rawValue,
                date: fixedNow,
                provider: "Dr. Smith",
                facility: "City Clinic",
                notes: "Routine",
                labResults: [
                    BackupLabResult(
                        catalogID: "hemoglobin",
                        customName: nil,
                        value: 13.9,
                        unit: "g/dL",
                        customLow: nil,
                        customHigh: nil,
                        date: fixedNow
                    )
                ],
                attachments: [
                    BackupAttachment(filename: "report.pdf", kind: AttachmentKind.pdf.rawValue, data: Data([0x25, 0x50, 0x44, 0x46]))
                ]
            )
        ]
        payload.vitals = [BackupVital(type: VitalType.weight.rawValue, value: 68, secondaryValue: nil, date: fixedNow, note: "")]
        payload.medications = [
            BackupMedication(
                name: "Warfarin",
                dosage: "5mg",
                frequency: "Once daily",
                purpose: "Anticoagulation",
                notes: "",
                startDate: fixedNow,
                endDate: nil,
                reminderEnabled: true,
                reminderTime: fixedNow
            )
        ]
        payload.symptoms = [BackupSymptom(name: "Headache", severity: 4, date: fixedNow, notes: "")]
        payload.appointments = [
            BackupAppointment(title: "Checkup", doctor: "Dr. Smith", location: "City Clinic", date: fixedNow, notes: "", reminderEnabled: false)
        ]
        payload.scoreSnapshots = [BackupScoreSnapshot(date: fixedNow, score: 88, criticalCount: 0, attentionCount: 1)]
        payload.goals = [
            BackupGoal(type: VitalType.weight.rawValue, targetValue: 65, startValue: 70, createdAt: fixedNow, targetDate: nil, note: "Lose weight", isActive: true)
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)

        XCTAssertEqual(decoded.version, payload.version)
        XCTAssertEqual(decoded.exportedAt, fixedNow)
        XCTAssertEqual(decoded.profile?.name, "Jane Doe")
        XCTAssertEqual(decoded.profile?.heightCm, 168)
        XCTAssertEqual(decoded.reports.count, 1)
        XCTAssertEqual(decoded.reports.first?.labResults.first?.value, 13.9)
        XCTAssertEqual(decoded.reports.first?.attachments.first?.filename, "report.pdf")
        XCTAssertEqual(decoded.vitals.first?.value, 68)
        XCTAssertEqual(decoded.medications.first?.name, "Warfarin")
        XCTAssertEqual(decoded.symptoms.first?.severity, 4)
        XCTAssertEqual(decoded.appointments.first?.title, "Checkup")
        XCTAssertEqual(decoded.scoreSnapshots.first?.score, 88)
        XCTAssertEqual(decoded.goals?.first?.targetValue, 65)
    }

    func testBackupPayloadDecodesWhenGoalsKeyIsMissing() throws {
        // Simulates a backup file created before `goals` existed: the key is
        // absent entirely. The optional `goals` property should decode to nil
        // rather than throwing.
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
        XCTAssertNil(decoded.goals)
        XCTAssertNil(decoded.profile)
        XCTAssertTrue(decoded.reports.isEmpty)
    }

    // MARK: Real BackupService.export / restore round trip

    func testExportAndRestoreRoundTripThroughRealService() throws {
        let profile = HealthProfile()
        profile.name = "Jane Doe"
        profile.heightCm = 168
        sourceContext.insert(profile)

        let report = MedicalReport(
            title: "Annual Bloodwork",
            category: .labReport,
            date: fixedNow,
            provider: "Dr. Smith",
            facility: "City Clinic",
            notes: "Routine"
        )
        sourceContext.insert(report)
        report.labResults.append(LabResult(catalogID: "hemoglobin", value: 13.9, unit: "g/dL", date: fixedNow))

        let vital = VitalSample(type: .weight, value: 68, date: fixedNow)
        sourceContext.insert(vital)

        let medication = Medication(name: "Warfarin", dosage: "5mg", startDate: fixedNow)
        sourceContext.insert(medication)

        let symptom = SymptomEntry(name: "Headache", severity: 4, date: fixedNow)
        sourceContext.insert(symptom)

        let appointment = Appointment(title: "Checkup", date: fixedNow.addingTimeInterval(86_400))
        sourceContext.insert(appointment)

        try sourceContext.save()

        let data = try BackupService.export(from: sourceContext, passphrase: "correct horse battery staple")

        let restoredCount = try BackupService.restore(from: data, passphrase: "correct horse battery staple", into: destinationContext)
        XCTAssertGreaterThan(restoredCount, 0)

        let restoredProfiles = try destinationContext.fetch(FetchDescriptor<HealthProfile>())
        XCTAssertEqual(restoredProfiles.first?.name, "Jane Doe")
        XCTAssertEqual(restoredProfiles.first?.heightCm, 168)

        let restoredReports = try destinationContext.fetch(FetchDescriptor<MedicalReport>())
        XCTAssertEqual(restoredReports.count, 1)
        XCTAssertEqual(restoredReports.first?.labResults.count, 1)
        XCTAssertEqual(restoredReports.first?.labResults.first?.value, 13.9)

        let restoredVitals = try destinationContext.fetch(FetchDescriptor<VitalSample>())
        XCTAssertEqual(restoredVitals.count, 1)
        XCTAssertEqual(restoredVitals.first?.value, 68)

        let restoredMedications = try destinationContext.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(restoredMedications.count, 1)
        XCTAssertEqual(restoredMedications.first?.name, "Warfarin")

        let restoredSymptoms = try destinationContext.fetch(FetchDescriptor<SymptomEntry>())
        XCTAssertEqual(restoredSymptoms.count, 1)

        let restoredAppointments = try destinationContext.fetch(FetchDescriptor<Appointment>())
        XCTAssertEqual(restoredAppointments.count, 1)
    }
}
