//
//  SampleData.swift
//  MediTrack
//
//  Demo / sample-data module. Populates the SwiftData store with a realistic
//  longitudinal health record for a fictional patient ("Alex") so the app can
//  be explored, screenshotted, and tested without hand-entering data. All dates
//  are computed relative to "now" via Calendar so the story stays fresh.
//
//  Nothing here is medical advice; every value is fabricated for demonstration.
//

import Foundation
import SwiftData

enum SampleData {

    // MARK: - Public API

    /// Inserts a realistic demo data set. Creates a demo `HealthProfile` ONLY if
    /// no profile exists yet (an existing profile is never overwritten).
    @MainActor static func load(into context: ModelContext) {

        // 1. Profile — only if none exists.
        let existingProfiles = (try? context.fetch(FetchDescriptor<HealthProfile>())) ?? []
        if existingProfiles.isEmpty {
            let profile = HealthProfile()
            profile.name = "Alex"
            profile.sex = .male
            var dob = DateComponents()
            dob.year = 1988
            dob.month = 5
            dob.day = 12
            profile.dateOfBirth = Calendar.current.date(from: dob)
            profile.heightCm = 178
            profile.bloodType = "O+"
            context.insert(profile)
        }

        // 2. Medical reports (+ their lab results).

        // Annual Physical — 14 months ago. Baseline panel with a few flags
        // (borderline lipids, low vitamin D).
        let annual = MedicalReport(
            title: "Annual Physical — Blood Panel",
            category: .labReport,
            date: monthsAgo(14),
            provider: "Dr. Chen",
            facility: "City Medical Center"
        )
        context.insert(annual)
        addLab("hemoglobin", 15.1, to: annual)
        addLab("fastingGlucose", 92, to: annual)
        addLab("hba1c", 5.4, to: annual)
        addLab("totalCholesterol", 224, to: annual)
        addLab("ldlCholesterol", 138, to: annual)
        addLab("hdlCholesterol", 42, to: annual)
        addLab("triglycerides", 160, to: annual)
        addLab("vitaminD", 18, to: annual)
        addLab("tsh", 2.1, to: annual)
        addLab("alt", 24, to: annual)
        addLab("creatinine", 1.0, to: annual)
        addLab("crp", 1.2, to: annual)

        // Follow-up lipid panel — 8 months ago. Lipids trending down.
        let lipidFollowUp = MedicalReport(
            title: "Follow-up Lipid Panel",
            category: .labReport,
            date: monthsAgo(8),
            provider: "Dr. Chen"
        )
        context.insert(lipidFollowUp)
        addLab("totalCholesterol", 208, to: lipidFollowUp)
        addLab("ldlCholesterol", 128, to: lipidFollowUp)
        addLab("hdlCholesterol", 45, to: lipidFollowUp)
        addLab("triglycerides", 145, to: lipidFollowUp)
        addLab("vitaminD", 24, to: lipidFollowUp)

        // Cardiology consultation — 6 months ago. No labs.
        let cardiology = MedicalReport(
            title: "Cardiology Consultation",
            category: .consultation,
            date: monthsAgo(6),
            provider: "Dr. Osei",
            notes: """
            Reviewed lipid trends and blood pressure history. Started home \
            blood-pressure monitoring with morning and evening readings. \
            Discussed lifestyle changes: reduced sodium, regular aerobic \
            exercise, and continued statin therapy. Follow up in six months.
            """
        )
        context.insert(cardiology)

        // Flu vaccination — 3 months ago. No labs.
        let flu = MedicalReport(
            title: "Flu Vaccination",
            category: .vaccination,
            date: monthsAgo(3),
            facility: "Neighborhood Pharmacy"
        )
        context.insert(flu)

        // Latest blood panel — 1 month ago. Lipids and vitamin D improved.
        let latest = MedicalReport(
            title: "Latest Blood Panel",
            category: .labReport,
            date: monthsAgo(1),
            provider: "Dr. Chen"
        )
        context.insert(latest)
        addLab("hemoglobin", 15.0, to: latest)
        addLab("fastingGlucose", 90, to: latest)
        addLab("hba1c", 5.3, to: latest)
        addLab("totalCholesterol", 186, to: latest)
        addLab("ldlCholesterol", 112, to: latest)
        addLab("hdlCholesterol", 49, to: latest)
        addLab("triglycerides", 130, to: latest)
        addLab("vitaminD", 34, to: latest)
        addLab("ferritin", 110, to: latest)
        addLab("crp", 0.8, to: latest)

        // 3. Vitals.

        // Weight (kg): 10 entries over ~12 months, declining 84.0 -> 80.5.
        let weightStart = 84.0
        let weightEnd = 80.5
        for i in 0..<10 {
            let frac = Double(i) / 9.0
            let raw = weightStart + (weightEnd - weightStart) * frac
            let value = (raw * 10).rounded() / 10
            let day = Int((1.0 - frac) * 350.0) + 7   // ~357 ... 7 days ago
            context.insert(VitalSample(type: .weight, value: value, date: daysAgo(day)))
        }

        // Blood pressure: 8 entries over ~6 months, improving 138/88 -> 124/79.
        let bpCount = 8
        for i in 0..<bpCount {
            let frac = Double(i) / Double(bpCount - 1)
            let systolic = (138.0 + (124.0 - 138.0) * frac).rounded()
            let diastolic = (88.0 + (79.0 - 88.0) * frac).rounded()
            let day = Int((1.0 - frac) * 180.0) + 5    // ~185 ... 5 days ago
            context.insert(VitalSample(
                type: .bloodPressure,
                value: systolic,
                secondaryValue: diastolic,
                date: daysAgo(day)
            ))
        }

        // Resting heart rate: 4 entries over 4 months, 74 -> 66 bpm.
        let heartRate: [(value: Double, monthsAgo: Int)] = [
            (74, 4), (72, 3), (69, 2), (66, 1)
        ]
        for entry in heartRate {
            context.insert(VitalSample(type: .heartRate, value: entry.value, date: monthsAgo(entry.monthsAgo)))
        }

        // Blood glucose: 3 entries over 3 months, ~94 -> 89 mg/dL.
        let glucose: [(value: Double, monthsAgo: Int)] = [
            (94, 3), (91, 2), (89, 1)
        ]
        for entry in glucose {
            context.insert(VitalSample(type: .bloodGlucose, value: entry.value, date: monthsAgo(entry.monthsAgo)))
        }

        // Oxygen saturation: 2 entries, 97% then 98%.
        context.insert(VitalSample(type: .oxygenSaturation, value: 97, date: monthsAgo(2)))
        context.insert(VitalSample(type: .oxygenSaturation, value: 98, date: monthsAgo(1)))

        // Body temperature: 1 entry, 36.6 °C, two weeks ago.
        context.insert(VitalSample(type: .temperature, value: 36.6, date: daysAgo(14)))

        // Respiratory rate: 2 entries, 16 then 15 breaths/min.
        context.insert(VitalSample(type: .respiratoryRate, value: 16, date: monthsAgo(2)))
        context.insert(VitalSample(type: .respiratoryRate, value: 15, date: monthsAgo(1)))

        // Sleep: 6 entries over ~3 months, improving 6.2 -> 7.4 hours.
        let sleep: [(value: Double, daysAgo: Int)] = [
            (6.2, 90), (6.4, 75), (6.7, 60), (6.9, 45), (7.2, 25), (7.4, 10)
        ]
        for entry in sleep {
            context.insert(VitalSample(type: .sleepHours, value: entry.value, date: daysAgo(entry.daysAgo)))
        }

        // 4. Medications.

        // Atorvastatin — active, started 8 months ago.
        context.insert(Medication(
            name: "Atorvastatin",
            dosage: "10 mg",
            frequency: "Once daily",
            purpose: "Cholesterol",
            startDate: monthsAgo(8)
        ))

        // Vitamin D3 — active, started 8 months ago.
        context.insert(Medication(
            name: "Vitamin D3",
            dosage: "2000 IU",
            frequency: "Once daily",
            purpose: "Vitamin D deficiency",
            startDate: monthsAgo(8)
        ))

        // Amoxicillin — a completed 10-day course ~13 months ago.
        let amoxStart = monthsAgo(13)
        let amoxEnd = Calendar.current.date(byAdding: .day, value: 10, to: amoxStart) ?? amoxStart
        context.insert(Medication(
            name: "Amoxicillin",
            dosage: "500 mg",
            frequency: "Three times daily",
            purpose: "Sinus infection",
            startDate: amoxStart,
            endDate: amoxEnd
        ))

        // 5. Symptoms — a mild improvement story over the past two months.
        context.insert(SymptomEntry(name: "Headache", severity: 6, date: monthsAgo(2), notes: "After long screen days"))
        context.insert(SymptomEntry(name: "Headache", severity: 5, date: daysAgo(42)))
        context.insert(SymptomEntry(name: "Fatigue", severity: 5, date: daysAgo(35)))
        context.insert(SymptomEntry(name: "Headache", severity: 4, date: daysAgo(21)))
        context.insert(SymptomEntry(name: "Back Pain", severity: 3, date: daysAgo(14), notes: "After gym session"))
        context.insert(SymptomEntry(name: "Headache", severity: 3, date: daysAgo(5)))

        // 6. Appointments.

        // Upcoming — cardiology follow-up in ~3 weeks. Reminder OFF so sample
        // data never schedules a real notification.
        context.insert(Appointment(
            title: "Cardiology Follow-up",
            doctor: "Dr. Osei",
            location: "City Medical Center",
            date: Calendar.current.date(byAdding: .day, value: 21, to: .now) ?? .now,
            notes: "Bring home blood-pressure log.",
            reminderEnabled: false
        ))

        // Past — annual physical ~14 months ago.
        context.insert(Appointment(
            title: "Annual Physical",
            doctor: "Dr. Chen",
            location: "City Medical Center",
            date: monthsAgo(14),
            reminderEnabled: false
        ))

        // 7. Goals.
        context.insert(HealthGoal(
            type: .weight,
            targetValue: 78,
            startValue: 84,
            targetDate: Calendar.current.date(byAdding: .month, value: 2, to: .now),
            note: "Doctor-recommended target"
        ))
        context.insert(HealthGoal(
            type: .sleepHours,
            targetValue: 7.5,
            startValue: 6.2
        ))
    }

    /// Deletes ALL data of every model type.
    @MainActor static func eraseAllData(in context: ModelContext) {
        try? context.delete(model: MedicalReport.self)
        try? context.delete(model: LabResult.self)
        try? context.delete(model: ReportAttachment.self)
        try? context.delete(model: VitalSample.self)
        try? context.delete(model: Medication.self)
        try? context.delete(model: SymptomEntry.self)
        try? context.delete(model: Appointment.self)
        try? context.delete(model: HealthProfile.self)
        try? context.delete(model: ScoreSnapshot.self)
        try? context.delete(model: HealthGoal.self)
        try? context.delete(model: Reminder.self)
        try? context.delete(model: ReminderCompletion.self)
    }

    // MARK: - Helpers

    /// Appends a catalog-backed lab result to `report`, using the catalog's
    /// exact unit string and matching the report's date.
    private static func addLab(_ catalogID: String, _ value: Double, to report: MedicalReport) {
        let unit = LabCatalog.reference(for: catalogID)?.unit ?? ""
        report.labResults.append(
            LabResult(catalogID: catalogID, value: value, unit: unit, date: report.date)
        )
    }

    private static func monthsAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -n, to: .now) ?? .now
    }

    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now
    }
}
