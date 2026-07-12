import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Backup payload (versioned, Codable)

struct BackupPayload: Codable {
    var version: Int = 1
    var exportedAt: Date = .now
    var profile: BackupProfile?
    var reports: [BackupReport] = []
    var vitals: [BackupVital] = []
    var medications: [BackupMedication] = []
    var symptoms: [BackupSymptom] = []
    var appointments: [BackupAppointment] = []
    var scoreSnapshots: [BackupScoreSnapshot] = []
    /// Optional so backups made before goals existed still decode.
    var goals: [BackupGoal]? = []
    /// Optional so backups made before reminders existed still decode.
    var reminders: [BackupReminder]? = []
}

struct BackupGoal: Codable {
    var type: String
    var targetValue: Double
    var startValue: Double?
    var createdAt: Date
    var targetDate: Date?
    var note: String
    var isActive: Bool
}

struct BackupProfile: Codable {
    var name: String
    var dateOfBirth: Date?
    var sex: String
    var heightCm: Double?
    var bloodType: String
    var allergies: String
    var conditions: String
    /// Quiz-derived fields. Optional so backups made before the onboarding
    /// quiz existed still decode; nil is treated as "unset" on restore.
    var activityLevel: String?
    var typicalSleepHours: Double?
    var dietStyle: String?
    var exerciseDaysPerWeek: Int?
    var healthGoalTags: [String]?
    var healthConcerns: [String]?
    var supplements: [String]?
    var hasCompletedQuiz: Bool?
}

struct BackupReminder: Codable {
    var title: String
    var detail: String
    var systemImage: String
    var timeOfDay: Date?
    var isAISuggested: Bool
    var suggestionReason: String
    var isActive: Bool
    var createdAt: Date
    /// Dates of logged completions, day-granularity comparison is done by `Reminder.isCompleted(on:)`.
    var completions: [Date]
}

struct BackupLabResult: Codable {
    var catalogID: String?
    var customName: String?
    var value: Double
    var unit: String
    var customLow: Double?
    var customHigh: Double?
    var date: Date
}

struct BackupAttachment: Codable {
    var filename: String
    var kind: String
    var data: Data
}

struct BackupReport: Codable {
    var title: String
    var category: String
    var date: Date
    var provider: String
    var facility: String
    var notes: String
    var labResults: [BackupLabResult]
    var attachments: [BackupAttachment]
}

struct BackupVital: Codable {
    var type: String
    var value: Double
    var secondaryValue: Double?
    var date: Date
    var note: String
}

struct BackupMedication: Codable {
    var name: String
    var dosage: String
    var frequency: String
    var purpose: String
    var notes: String
    var startDate: Date
    var endDate: Date?
    var reminderEnabled: Bool
    var reminderTime: Date?
}

struct BackupSymptom: Codable {
    var name: String
    var severity: Int
    var date: Date
    var notes: String
}

struct BackupAppointment: Codable {
    var title: String
    var doctor: String
    var location: String
    var date: Date
    var notes: String
    var reminderEnabled: Bool
}

struct BackupScoreSnapshot: Codable {
    var date: Date
    var score: Int
    var criticalCount: Int
    var attentionCount: Int
}

enum BackupError: LocalizedError {
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected file couldn't be read as a MediTrack backup."
        }
    }
}

// MARK: - Backup service

enum BackupService {

    /// Serializes the entire store (including attachments) to JSON.
    @MainActor
    static func export(from context: ModelContext) throws -> Data {
        var payload = BackupPayload()

        if let profile = try context.fetch(FetchDescriptor<HealthProfile>()).first {
            payload.profile = BackupProfile(
                name: profile.name,
                dateOfBirth: profile.dateOfBirth,
                sex: profile.sexRaw,
                heightCm: profile.heightCm,
                bloodType: profile.bloodType,
                allergies: profile.allergies,
                conditions: profile.conditions,
                activityLevel: profile.activityLevel,
                typicalSleepHours: profile.typicalSleepHours,
                dietStyle: profile.dietStyle,
                exerciseDaysPerWeek: profile.exerciseDaysPerWeek,
                healthGoalTags: profile.healthGoalTags,
                healthConcerns: profile.healthConcerns,
                supplements: profile.supplements,
                hasCompletedQuiz: profile.hasCompletedQuiz
            )
        }

        payload.reports = try context.fetch(FetchDescriptor<MedicalReport>()).map { report in
            BackupReport(
                title: report.title,
                category: report.categoryRaw,
                date: report.date,
                provider: report.provider,
                facility: report.facility,
                notes: report.notes,
                labResults: report.labResults.map {
                    BackupLabResult(
                        catalogID: $0.catalogID,
                        customName: $0.customName,
                        value: $0.value,
                        unit: $0.unit,
                        customLow: $0.customLow,
                        customHigh: $0.customHigh,
                        date: $0.date
                    )
                },
                attachments: report.attachments.map {
                    BackupAttachment(filename: $0.filename, kind: $0.kindRaw, data: $0.data)
                }
            )
        }
        payload.vitals = try context.fetch(FetchDescriptor<VitalSample>()).map {
            BackupVital(type: $0.typeRaw, value: $0.value, secondaryValue: $0.secondaryValue, date: $0.date, note: $0.note)
        }
        payload.medications = try context.fetch(FetchDescriptor<Medication>()).map {
            BackupMedication(
                name: $0.name,
                dosage: $0.dosage,
                frequency: $0.frequency,
                purpose: $0.purpose,
                notes: $0.notes,
                startDate: $0.startDate,
                endDate: $0.endDate,
                reminderEnabled: $0.reminderEnabled,
                reminderTime: $0.reminderTime
            )
        }
        payload.symptoms = try context.fetch(FetchDescriptor<SymptomEntry>()).map {
            BackupSymptom(name: $0.name, severity: $0.severity, date: $0.date, notes: $0.notes)
        }
        payload.appointments = try context.fetch(FetchDescriptor<Appointment>()).map {
            BackupAppointment(
                title: $0.title,
                doctor: $0.doctor,
                location: $0.location,
                date: $0.date,
                notes: $0.notes,
                reminderEnabled: $0.reminderEnabled
            )
        }
        payload.scoreSnapshots = try context.fetch(FetchDescriptor<ScoreSnapshot>()).map {
            BackupScoreSnapshot(date: $0.date, score: $0.score, criticalCount: $0.criticalCount, attentionCount: $0.attentionCount)
        }
        payload.goals = try context.fetch(FetchDescriptor<HealthGoal>()).map {
            BackupGoal(
                type: $0.typeRaw,
                targetValue: $0.targetValue,
                startValue: $0.startValue,
                createdAt: $0.createdAt,
                targetDate: $0.targetDate,
                note: $0.note,
                isActive: $0.isActive
            )
        }
        payload.reminders = try context.fetch(FetchDescriptor<Reminder>()).map { reminder in
            BackupReminder(
                title: reminder.title,
                detail: reminder.detail,
                systemImage: reminder.systemImage,
                timeOfDay: reminder.timeOfDay,
                isAISuggested: reminder.isAISuggested,
                suggestionReason: reminder.suggestionReason,
                isActive: reminder.isActive,
                createdAt: reminder.createdAt,
                completions: (reminder.completions ?? []).map { $0.date }
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Replaces all current data with the backup contents and returns the
    /// number of restored records. The existing profile object is updated
    /// in place (not deleted) so views bound to it stay valid. Notification
    /// reminders are NOT rescheduled automatically.
    @MainActor
    @discardableResult
    static func restore(from data: Data, into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else {
            throw BackupError.unreadableFile
        }

        // Wipe everything except the profile object itself.
        try? context.delete(model: MedicalReport.self)
        try? context.delete(model: LabResult.self)
        try? context.delete(model: ReportAttachment.self)
        try? context.delete(model: VitalSample.self)
        try? context.delete(model: Medication.self)
        try? context.delete(model: SymptomEntry.self)
        try? context.delete(model: Appointment.self)
        try? context.delete(model: ScoreSnapshot.self)
        try? context.delete(model: HealthGoal.self)
        try? context.delete(model: Reminder.self)
        try? context.delete(model: ReminderCompletion.self)

        // Update the profile in place (or create one).
        let existingProfile = (try? context.fetch(FetchDescriptor<HealthProfile>()))?.first
        let profile: HealthProfile
        if let existingProfile {
            profile = existingProfile
        } else {
            profile = HealthProfile()
            context.insert(profile)
        }
        if let dto = payload.profile {
            profile.name = dto.name
            profile.dateOfBirth = dto.dateOfBirth
            profile.sexRaw = dto.sex
            profile.heightCm = dto.heightCm
            profile.bloodType = dto.bloodType
            profile.allergies = dto.allergies
            profile.conditions = dto.conditions
            profile.activityLevel = dto.activityLevel ?? ""
            profile.typicalSleepHours = dto.typicalSleepHours ?? 0
            profile.dietStyle = dto.dietStyle ?? ""
            profile.exerciseDaysPerWeek = dto.exerciseDaysPerWeek ?? 0
            profile.healthGoalTags = dto.healthGoalTags ?? []
            profile.healthConcerns = dto.healthConcerns ?? []
            profile.supplements = dto.supplements ?? []
            profile.hasCompletedQuiz = dto.hasCompletedQuiz ?? false
        } else {
            profile.name = ""
            profile.dateOfBirth = nil
            profile.sexRaw = BiologicalSex.unspecified.rawValue
            profile.heightCm = nil
            profile.bloodType = ""
            profile.allergies = ""
            profile.conditions = ""
            profile.activityLevel = ""
            profile.typicalSleepHours = 0
            profile.dietStyle = ""
            profile.exerciseDaysPerWeek = 0
            profile.healthGoalTags = []
            profile.healthConcerns = []
            profile.supplements = []
            profile.hasCompletedQuiz = false
        }

        var restored = 0

        for dto in payload.reports {
            let report = MedicalReport(
                title: dto.title,
                category: ReportCategory(rawValue: dto.category) ?? .other,
                date: dto.date,
                provider: dto.provider,
                facility: dto.facility,
                notes: dto.notes
            )
            context.insert(report)
            for lab in dto.labResults {
                report.labResults.append(LabResult(
                    catalogID: lab.catalogID,
                    customName: lab.customName,
                    value: lab.value,
                    unit: lab.unit,
                    customLow: lab.customLow,
                    customHigh: lab.customHigh,
                    date: lab.date
                ))
            }
            for attachment in dto.attachments {
                report.attachments.append(ReportAttachment(
                    filename: attachment.filename,
                    kind: AttachmentKind(rawValue: attachment.kind) ?? .image,
                    data: attachment.data
                ))
            }
            restored += 1
        }

        for dto in payload.vitals {
            context.insert(VitalSample(
                type: VitalType(rawValue: dto.type) ?? .weight,
                value: dto.value,
                secondaryValue: dto.secondaryValue,
                date: dto.date,
                note: dto.note
            ))
            restored += 1
        }

        for dto in payload.medications {
            let medication = Medication(
                name: dto.name,
                dosage: dto.dosage,
                frequency: dto.frequency,
                purpose: dto.purpose,
                notes: dto.notes,
                startDate: dto.startDate,
                endDate: dto.endDate
            )
            medication.reminderEnabled = dto.reminderEnabled
            medication.reminderTime = dto.reminderTime
            context.insert(medication)
            restored += 1
        }

        for dto in payload.symptoms {
            context.insert(SymptomEntry(name: dto.name, severity: dto.severity, date: dto.date, notes: dto.notes))
            restored += 1
        }

        for dto in payload.appointments {
            context.insert(Appointment(
                title: dto.title,
                doctor: dto.doctor,
                location: dto.location,
                date: dto.date,
                notes: dto.notes,
                reminderEnabled: dto.reminderEnabled
            ))
            restored += 1
        }

        for dto in payload.scoreSnapshots {
            context.insert(ScoreSnapshot(
                date: dto.date,
                score: dto.score,
                criticalCount: dto.criticalCount,
                attentionCount: dto.attentionCount
            ))
            restored += 1
        }

        for dto in payload.goals ?? [] {
            let goal = HealthGoal(
                type: VitalType(rawValue: dto.type) ?? .weight,
                targetValue: dto.targetValue,
                startValue: dto.startValue,
                targetDate: dto.targetDate,
                note: dto.note
            )
            goal.createdAt = dto.createdAt
            goal.isActive = dto.isActive
            context.insert(goal)
            restored += 1
        }

        for dto in payload.reminders ?? [] {
            let reminder = Reminder(
                title: dto.title,
                detail: dto.detail,
                systemImage: dto.systemImage,
                timeOfDay: dto.timeOfDay,
                isAISuggested: dto.isAISuggested,
                suggestionReason: dto.suggestionReason,
                isActive: dto.isActive
            )
            reminder.createdAt = dto.createdAt
            context.insert(reminder)
            for completionDate in dto.completions {
                reminder.completions?.append(ReminderCompletion(date: completionDate))
            }
            restored += 1
        }

        return restored
    }
}

// MARK: - FileDocument wrapper for the exporter

struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
