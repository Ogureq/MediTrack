import Foundation
import SwiftData

// MARK: - Report category

enum ReportCategory: String, Codable, CaseIterable, Identifiable {
    case labReport
    case imaging
    case prescription
    case consultation
    case vaccination
    case procedure
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .labReport: "Lab Report"
        case .imaging: "Imaging"
        case .prescription: "Prescription"
        case .consultation: "Consultation"
        case .vaccination: "Vaccination"
        case .procedure: "Procedure"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .labReport: "testtube.2"
        case .imaging: "photo.on.rectangle.angled"
        case .prescription: "pills.fill"
        case .consultation: "stethoscope"
        case .vaccination: "syringe"
        case .procedure: "cross.case.fill"
        case .other: "doc.text.fill"
        }
    }
}

// MARK: - Medical report

@Model
final class MedicalReport {
    var title: String = ""
    var categoryRaw: String = ReportCategory.other.rawValue
    var date: Date = Date.now
    var provider: String = ""
    var facility: String = ""
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \LabResult.report)
    var labResults: [LabResult] = []

    @Relationship(deleteRule: .cascade, inverse: \ReportAttachment.report)
    var attachments: [ReportAttachment] = []

    var category: ReportCategory {
        get { ReportCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        title: String,
        category: ReportCategory = .labReport,
        date: Date = .now,
        provider: String = "",
        facility: String = "",
        notes: String = ""
    ) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.date = date
        self.provider = provider
        self.facility = facility
        self.notes = notes
    }
}

// MARK: - Lab result

@Model
final class LabResult {
    /// Key into `LabCatalog` when the test was picked from the built-in catalog.
    var catalogID: String?
    /// Name of the test when entered manually.
    var customName: String?
    var value: Double = 0
    var unit: String = ""
    var customLow: Double?
    var customHigh: Double?
    var date: Date = Date.now
    var report: MedicalReport?

    init(
        catalogID: String? = nil,
        customName: String? = nil,
        value: Double,
        unit: String,
        customLow: Double? = nil,
        customHigh: Double? = nil,
        date: Date = .now
    ) {
        self.catalogID = catalogID
        self.customName = customName
        self.value = value
        self.unit = unit
        self.customLow = customLow
        self.customHigh = customHigh
        self.date = date
    }

    var catalogReference: LabReference? {
        guard let catalogID else { return nil }
        return LabCatalog.reference(for: catalogID)
    }

    var displayName: String {
        catalogReference?.name ?? customName ?? "Unknown Test"
    }

    /// Stable key used to group results of the same test across reports.
    var seriesKey: String {
        if let catalogID { return catalogID.lowercased() }
        return "custom:\(customName?.lowercased() ?? "unknown")"
    }

    func referenceRange(for sex: BiologicalSex?) -> ClosedRange<Double>? {
        if let customLow, let customHigh, customLow <= customHigh {
            return customLow...customHigh
        }
        return catalogReference?.referenceRange(for: sex)
    }
}

// MARK: - Report attachment

enum AttachmentKind: String, Codable {
    case image
    case pdf
}

@Model
final class ReportAttachment {
    var filename: String = ""
    var kindRaw: String = AttachmentKind.image.rawValue
    @Attribute(.externalStorage) var data: Data = Data()
    var report: MedicalReport?

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .image }
        set { kindRaw = newValue.rawValue }
    }

    init(filename: String, kind: AttachmentKind, data: Data) {
        self.filename = filename
        self.kindRaw = kind.rawValue
        self.data = data
    }
}

// MARK: - Vitals

enum VitalType: String, Codable, CaseIterable, Identifiable {
    case weight
    case bloodPressure
    case heartRate
    case bloodGlucose
    case oxygenSaturation
    case temperature
    case respiratoryRate
    case sleepHours

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weight: "Weight"
        case .bloodPressure: "Blood Pressure"
        case .heartRate: "Resting Heart Rate"
        case .bloodGlucose: "Blood Glucose"
        case .oxygenSaturation: "Oxygen Saturation"
        case .temperature: "Body Temperature"
        case .respiratoryRate: "Respiratory Rate"
        case .sleepHours: "Sleep"
        }
    }

    var unit: String {
        switch self {
        case .weight: "kg"
        case .bloodPressure: "mmHg"
        case .heartRate: "bpm"
        case .bloodGlucose: "mg/dL"
        case .oxygenSaturation: "%"
        case .temperature: "°C"
        case .respiratoryRate: "breaths/min"
        case .sleepHours: "hours"
        }
    }

    var systemImage: String {
        switch self {
        case .weight: "scalemass.fill"
        case .bloodPressure: "waveform.path.ecg"
        case .heartRate: "heart.fill"
        case .bloodGlucose: "drop.fill"
        case .oxygenSaturation: "lungs.fill"
        case .temperature: "thermometer.medium"
        case .respiratoryRate: "wind"
        case .sleepHours: "bed.double.fill"
        }
    }

    /// Typical healthy range for the primary value, used for chart bands and trend analysis.
    var healthyRange: ClosedRange<Double>? {
        switch self {
        case .weight: nil
        case .bloodPressure: 90...120
        case .heartRate: 50...100
        case .bloodGlucose: 70...140
        case .oxygenSaturation: 95...100
        case .temperature: 36.1...37.2
        case .respiratoryRate: 12...20
        case .sleepHours: 7...9
        }
    }

    var usesSecondaryValue: Bool { self == .bloodPressure }
}

@Model
final class VitalSample {
    var typeRaw: String = VitalType.weight.rawValue
    var value: Double = 0
    /// Diastolic pressure when `type == .bloodPressure`.
    var secondaryValue: Double?
    var date: Date = Date.now
    var note: String = ""

    var type: VitalType {
        get { VitalType(rawValue: typeRaw) ?? .weight }
        set { typeRaw = newValue.rawValue }
    }

    init(type: VitalType, value: Double, secondaryValue: Double? = nil, date: Date = .now, note: String = "") {
        self.typeRaw = type.rawValue
        self.value = value
        self.secondaryValue = secondaryValue
        self.date = date
        self.note = note
    }

    var formattedValue: String {
        if type == .bloodPressure, let secondaryValue {
            return "\(Int(value))/\(Int(secondaryValue)) \(type.unit)"
        }
        return Units.formatted(value, for: type)
    }
}

// MARK: - Medication

@Model
final class Medication {
    var name: String = ""
    var dosage: String = ""
    var frequency: String = ""
    var purpose: String = ""
    var notes: String = ""
    var startDate: Date = Date.now
    var endDate: Date?
    var reminderEnabled: Bool = false
    /// Time of day for the daily reminder (only hour/minute are relevant).
    var reminderTime: Date?
    /// Stable identifier used for the scheduled local notification.
    var reminderID: String = UUID().uuidString

    init(
        name: String,
        dosage: String = "",
        frequency: String = "",
        purpose: String = "",
        notes: String = "",
        startDate: Date = .now,
        endDate: Date? = nil
    ) {
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.purpose = purpose
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
    }

    var isActive: Bool {
        guard let endDate else { return true }
        return endDate > .now
    }
}

// MARK: - Health goal

/// A personal target for one vital (e.g. reach 78 kg, sleep 7.5 h).
/// Values are stored in canonical units, like `VitalSample`.
@Model
final class HealthGoal {
    var typeRaw: String = VitalType.weight.rawValue
    var targetValue: Double = 0
    /// The latest vital value when the goal was created, used for progress.
    var startValue: Double?
    var createdAt: Date = Date.now
    var targetDate: Date?
    var note: String = ""
    var isActive: Bool = true

    var type: VitalType {
        get { VitalType(rawValue: typeRaw) ?? .weight }
        set { typeRaw = newValue.rawValue }
    }

    init(
        type: VitalType,
        targetValue: Double,
        startValue: Double? = nil,
        targetDate: Date? = nil,
        note: String = ""
    ) {
        self.typeRaw = type.rawValue
        self.targetValue = targetValue
        self.startValue = startValue
        self.targetDate = targetDate
        self.note = note
    }

    /// Fraction of the way from the start value to the target, given the
    /// latest reading. Nil when there is no start value to measure from.
    func progress(latest: Double?) -> Double? {
        guard let startValue, let latest, abs(startValue - targetValue) > 1e-9 else { return nil }
        let fraction = (startValue - latest) / (startValue - targetValue)
        return min(1, max(0, fraction))
    }

    func isAchieved(latest: Double?) -> Bool {
        guard let latest else { return false }
        if let startValue {
            return targetValue <= startValue ? latest <= targetValue : latest >= targetValue
        }
        return abs(latest - targetValue) < 1e-9
    }
}

// MARK: - Symptom journal

@Model
final class SymptomEntry {
    var name: String = ""
    /// Self-rated severity 1...10.
    var severity: Int = 5
    var date: Date = Date.now
    var notes: String = ""

    init(name: String, severity: Int, date: Date = .now, notes: String = "") {
        self.name = name
        self.severity = min(10, max(1, severity))
        self.date = date
        self.notes = notes
    }
}

// MARK: - Appointment

@Model
final class Appointment {
    var title: String = ""
    var doctor: String = ""
    var location: String = ""
    var date: Date = Date.now
    var notes: String = ""
    var reminderEnabled: Bool = false
    /// Stable identifier used for the scheduled local notification.
    var reminderID: String = UUID().uuidString

    init(
        title: String,
        doctor: String = "",
        location: String = "",
        date: Date,
        notes: String = "",
        reminderEnabled: Bool = false
    ) {
        self.title = title
        self.doctor = doctor
        self.location = location
        self.date = date
        self.notes = notes
        self.reminderEnabled = reminderEnabled
    }

    var isUpcoming: Bool {
        date > .now
    }
}

// MARK: - Score snapshot

/// A point-in-time record of the generated health score, used to chart
/// score history on the dashboard. At most one snapshot per day is kept.
@Model
final class ScoreSnapshot {
    var date: Date = Date.now
    var score: Int = 0
    var criticalCount: Int = 0
    var attentionCount: Int = 0

    init(date: Date = .now, score: Int, criticalCount: Int = 0, attentionCount: Int = 0) {
        self.date = date
        self.score = score
        self.criticalCount = criticalCount
        self.attentionCount = attentionCount
    }
}

// MARK: - Health profile

@Model
final class HealthProfile {
    var name: String = ""
    var dateOfBirth: Date?
    var sexRaw: String = BiologicalSex.unspecified.rawValue
    var heightCm: Double?
    var bloodType: String = ""
    var allergies: String = ""
    var conditions: String = ""

    // Quiz-derived lifestyle fields. All default so existing stores migrate
    // cleanly via SwiftData lightweight migration; `typicalSleepHours == 0`
    // and `activityLevel == ""` both mean "unset".
    var activityLevel: String = ""
    var typicalSleepHours: Double = 0
    var dietStyle: String = ""
    var exerciseDaysPerWeek: Int = 0
    var healthGoalTags: [String] = []
    var healthConcerns: [String] = []
    var supplements: [String] = []
    var hasCompletedQuiz: Bool = false

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }

    init(
        activityLevel: String = "",
        typicalSleepHours: Double = 0,
        dietStyle: String = "",
        exerciseDaysPerWeek: Int = 0,
        healthGoalTags: [String] = [],
        healthConcerns: [String] = [],
        supplements: [String] = [],
        hasCompletedQuiz: Bool = false
    ) {
        self.activityLevel = activityLevel
        self.typicalSleepHours = typicalSleepHours
        self.dietStyle = dietStyle
        self.exerciseDaysPerWeek = exerciseDaysPerWeek
        self.healthGoalTags = healthGoalTags
        self.healthConcerns = healthConcerns
        self.supplements = supplements
        self.hasCompletedQuiz = hasCompletedQuiz
    }

    var age: Int? {
        guard let dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year
    }
}

// MARK: - Activity level

/// Self-reported activity level captured by the onboarding quiz.
enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary
    case light
    case moderate
    case active

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly Active"
        case .moderate: "Moderately Active"
        case .active: "Very Active"
        }
    }
}

// MARK: - Reminder

@Model
final class Reminder {
    var title: String = ""
    var detail: String = ""
    var systemImage: String = "pills.fill"
    /// Time of day for the notification (only hour/minute are relevant); nil means no notification.
    var timeOfDay: Date?
    var isAISuggested: Bool = false
    /// Educational rationale shown for AI-suggested items.
    var suggestionReason: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date.now
    /// Stable identifier used for the scheduled local notification.
    var reminderID: String = UUID().uuidString

    @Relationship(deleteRule: .cascade, inverse: \ReminderCompletion.reminder)
    var completions: [ReminderCompletion]? = []

    init(
        title: String,
        detail: String = "",
        systemImage: String = "pills.fill",
        timeOfDay: Date? = nil,
        isAISuggested: Bool = false,
        suggestionReason: String = "",
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.timeOfDay = timeOfDay
        self.isAISuggested = isAISuggested
        self.suggestionReason = suggestionReason
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// Whether a completion was logged for the given calendar day.
    func isCompleted(on day: Date, calendar: Calendar = .current) -> Bool {
        (completions ?? []).contains { calendar.isDate($0.date, inSameDayAs: day) }
    }
}

// MARK: - Reminder completion

@Model
final class ReminderCompletion {
    var date: Date = Date.now
    var reminder: Reminder?

    init(date: Date = .now, reminder: Reminder? = nil) {
        self.date = date
        self.reminder = reminder
    }
}

// MARK: - Formatting helpers

extension Double {
    /// Compact numeric formatting: up to 2 decimals, no trailing zeros.
    var compactFormatted: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }
}
