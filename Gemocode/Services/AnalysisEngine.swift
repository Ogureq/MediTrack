import Foundation

// MARK: - Review building blocks

enum Severity: Int, Comparable, CaseIterable, Identifiable {
    case info = 0
    case attention = 1
    case critical = 2

    var id: Int { rawValue }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .info: "Informational"
        case .attention: "Needs Attention"
        case .critical: "Critical"
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

enum FindingCategory: String {
    case labs = "Lab Results"
    case vitals = "Vitals"
    case trends = "Trends"
    case medications = "Medications"
    case general = "General"
}

struct Finding: Identifiable {
    let id = UUID()
    let severity: Severity
    let category: FindingCategory
    let title: String
    let detail: String
    let recommendation: String?
}

enum LabStatus {
    case criticalLow
    case low
    case normal
    case high
    case criticalHigh
    case unknown

    var label: String {
        switch self {
        case .criticalLow: "Critical Low"
        case .low: "Low"
        case .normal: "In Range"
        case .high: "High"
        case .criticalHigh: "Critical High"
        case .unknown: "No Range"
        }
    }

    var isOutOfRange: Bool {
        switch self {
        case .low, .high, .criticalLow, .criticalHigh: true
        case .normal, .unknown: false
        }
    }

    var isCritical: Bool {
        self == .criticalLow || self == .criticalHigh
    }
}

enum TrendDirection {
    case improving
    case worsening
    case stable
    case rising
    case falling

    var displayName: String {
        switch self {
        case .improving: "Improving"
        case .worsening: "Worsening"
        case .stable: "Stable"
        case .rising: "Rising"
        case .falling: "Falling"
        }
    }

    var systemImage: String {
        switch self {
        case .improving: "arrow.up.right.circle.fill"
        case .worsening: "arrow.down.right.circle.fill"
        case .stable: "equal.circle.fill"
        case .rising: "arrow.up.circle.fill"
        case .falling: "arrow.down.circle.fill"
        }
    }

    var isConcern: Bool { self == .worsening }
}

struct TrendInsight: Identifiable {
    let id = UUID()
    let metricName: String
    let unit: String
    let direction: TrendDirection
    let percentChange: Double
    let pointCount: Int
    let detail: String
}

/// The most recent value of one lab test, evaluated against its reference range.
struct LabSnapshot: Identifiable {
    let id: String
    let name: String
    let unit: String
    let value: Double
    let date: Date
    let status: LabStatus
    let range: ClosedRange<Double>?
    let reference: LabReference?
}

enum BloodPressureCategory {
    case normal
    case elevated
    case stage1
    case stage2
    case crisis

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .stage1: "Hypertension Stage 1"
        case .stage2: "Hypertension Stage 2"
        case .crisis: "Hypertensive Crisis"
        }
    }
}

// MARK: - Health review

struct HealthReview {
    let generatedAt: Date
    let hasData: Bool
    let score: Int
    let summary: String
    let findings: [Finding]
    let trends: [TrendInsight]
    let labSnapshots: [LabSnapshot]

    static let disclaimer = """
        Gemocode provides educational information only. It is not a medical device, does not \
        provide a diagnosis, and is not a substitute for professional medical advice. Always \
        consult a qualified healthcare professional about your results and before making any \
        health decisions.
        """

    var criticalFindings: [Finding] { findings.filter { $0.severity == .critical } }
    var attentionFindings: [Finding] { findings.filter { $0.severity == .attention } }
    var infoFindings: [Finding] { findings.filter { $0.severity == .info } }

    var scoreLabel: String {
        switch score {
        case 90...100: "Excellent"
        case 75..<90: "Good"
        case 60..<75: "Fair"
        case 40..<60: "Needs Attention"
        default: "Talk to Your Doctor"
        }
    }

    var shareText: String {
        var lines: [String] = []
        lines.append("Gemocode Health Review — \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Overall score: \(score)/100 (\(scoreLabel))")
        lines.append("")
        lines.append(summary)
        for severity in [Severity.critical, .attention, .info] {
            let group = findings.filter { $0.severity == severity }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append(severity.displayName.uppercased())
            for finding in group {
                lines.append("• \(finding.title): \(finding.detail)")
                if let recommendation = finding.recommendation {
                    lines.append("  → \(recommendation)")
                }
            }
        }
        if !trends.isEmpty {
            lines.append("")
            lines.append("TRENDS")
            for trend in trends {
                lines.append("• \(trend.detail)")
            }
        }
        lines.append("")
        lines.append(Self.disclaimer)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Analysis engine

enum AnalysisEngine {

    // MARK: Single-value evaluation

    static func status(
        value: Double,
        range: ClosedRange<Double>?,
        criticalLow: Double? = nil,
        criticalHigh: Double? = nil
    ) -> LabStatus {
        if let criticalLow, value < criticalLow { return .criticalLow }
        if let criticalHigh, value > criticalHigh { return .criticalHigh }
        guard let range else { return .unknown }
        if value < range.lowerBound { return .low }
        if value > range.upperBound { return .high }
        return .normal
    }

    /// ACC/AHA blood pressure categories.
    static func bloodPressureCategory(systolic: Double, diastolic: Double) -> BloodPressureCategory {
        if systolic > 180 || diastolic > 120 { return .crisis }
        if systolic >= 140 || diastolic >= 90 { return .stage2 }
        if systolic >= 130 || diastolic >= 80 { return .stage1 }
        if systolic >= 120 { return .elevated }
        return .normal
    }

    static func bmi(weightKg: Double, heightCm: Double) -> Double? {
        guard weightKg > 0, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    static func bmiCategory(_ bmi: Double) -> (name: String, severity: Severity) {
        switch bmi {
        case ..<18.5: ("Underweight", .attention)
        case 18.5..<25: ("Normal weight", .info)
        case 25..<30: ("Overweight", .info)
        default: ("Obese", .attention)
        }
    }

    // MARK: Trends

    /// Least-squares slope in value units per day. Requires at least 2 points.
    static func slopePerDay(_ points: [(date: Date, value: Double)]) -> Double? {
        guard points.count >= 2, let start = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(start) / 86_400 }
        let ys = points.map { $0.value }
        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-9 else { return nil }
        return (n * sumXY - sumX * sumY) / denominator
    }

    /// Classifies the trajectory of a metric relative to its reference range.
    /// `points` must be sorted by date ascending and contain at least 3 entries.
    static func trend(
        points: [(date: Date, value: Double)],
        range: ClosedRange<Double>?
    ) -> (direction: TrendDirection, percentChange: Double)? {
        guard points.count >= 3,
              let first = points.first,
              let last = points.last,
              abs(first.value) > 1e-9 else { return nil }

        let percentChange = (last.value - first.value) / abs(first.value) * 100

        guard let range else {
            if abs(percentChange) < 5 { return (.stable, percentChange) }
            return (percentChange > 0 ? .rising : .falling, percentChange)
        }

        func distanceFromRange(_ value: Double) -> Double {
            if range.contains(value) { return 0 }
            return value < range.lowerBound ? range.lowerBound - value : value - range.upperBound
        }

        let firstDistance = distanceFromRange(first.value)
        let lastDistance = distanceFromRange(last.value)

        if firstDistance == 0 && lastDistance == 0 { return (.stable, percentChange) }
        if lastDistance < firstDistance { return (.improving, percentChange) }
        if lastDistance > firstDistance { return (.worsening, percentChange) }
        if abs(percentChange) < 5 { return (.stable, percentChange) }
        return (percentChange > 0 ? .rising : .falling, percentChange)
    }

    // MARK: Full review generation

    static func generateReview(
        profile: HealthProfile?,
        reports: [MedicalReport],
        vitals: [VitalSample],
        medications: [Medication],
        symptoms: [SymptomEntry] = [],
        appointments: [Appointment] = [],
        now: Date = .now
    ) -> HealthReview {
        let sex = profile?.sex
        var findings: [Finding] = []
        var trends: [TrendInsight] = []

        // --- Lab results: latest value per test + per-test trend ---
        let allResults = reports.flatMap { $0.labResults }
        let grouped = Dictionary(grouping: allResults) { $0.seriesKey }
        var snapshots: [LabSnapshot] = []

        for (key, results) in grouped {
            let sorted = results.sorted { $0.date < $1.date }
            guard let latest = sorted.last else { continue }

            let reference = latest.catalogReference
            let range = latest.referenceRange(for: sex)
            let labStatus = status(
                value: latest.value,
                range: range,
                criticalLow: reference?.criticalLow,
                criticalHigh: reference?.criticalHigh
            )

            snapshots.append(LabSnapshot(
                id: key,
                name: latest.displayName,
                unit: latest.unit,
                value: latest.value,
                date: latest.date,
                status: labStatus,
                range: range,
                reference: reference
            ))

            let rangeText = range.map { "\($0.lowerBound.compactFormatted)–\($0.upperBound.compactFormatted) \(latest.unit)" } ?? "no reference range"
            let valueText = "\(latest.value.compactFormatted) \(latest.unit)"

            switch labStatus {
            case .criticalLow, .criticalHigh:
                let meaning = labStatus == .criticalLow ? reference?.lowMeaning : reference?.highMeaning
                findings.append(Finding(
                    severity: .critical,
                    category: .labs,
                    title: "\(latest.displayName) is at a critical level",
                    detail: "Latest value \(valueText) (typical range \(rangeText)). \(meaning ?? "")",
                    recommendation: "Contact your healthcare provider promptly to review this result."
                ))
            case .low, .high:
                let meaning = labStatus == .low ? reference?.lowMeaning : reference?.highMeaning
                findings.append(Finding(
                    severity: .attention,
                    category: .labs,
                    title: "\(latest.displayName) is \(labStatus == .low ? "below" : "above") its reference range",
                    detail: "Latest value \(valueText) (typical range \(rangeText)). \(meaning ?? "")",
                    recommendation: "Worth discussing with your doctor at your next visit."
                ))
            case .normal, .unknown:
                break
            }

            let series = sorted.map { (date: $0.date, value: $0.value) }
            if let (direction, percentChange) = trend(points: series, range: range) {
                let changeText = String(format: "%+.0f%%", percentChange)
                let detail: String
                switch direction {
                case .improving:
                    detail = "\(latest.displayName) changed \(changeText) over \(sorted.count) entries and is moving toward its reference range."
                case .worsening:
                    detail = "\(latest.displayName) changed \(changeText) over \(sorted.count) entries and is moving away from its reference range."
                case .stable:
                    detail = "\(latest.displayName) is stable across \(sorted.count) entries."
                case .rising, .falling:
                    detail = "\(latest.displayName) changed \(changeText) over \(sorted.count) entries."
                }
                trends.append(TrendInsight(
                    metricName: latest.displayName,
                    unit: latest.unit,
                    direction: direction,
                    percentChange: percentChange,
                    pointCount: sorted.count,
                    detail: detail
                ))
                if direction == .worsening {
                    findings.append(Finding(
                        severity: .attention,
                        category: .trends,
                        title: "\(latest.displayName) is trending away from its range",
                        detail: detail,
                        recommendation: "Keep tracking this value and mention the trend to your doctor."
                    ))
                }
            }
        }

        snapshots.sort { lhs, rhs in
            if lhs.status.isCritical != rhs.status.isCritical { return lhs.status.isCritical }
            if lhs.status.isOutOfRange != rhs.status.isOutOfRange { return lhs.status.isOutOfRange }
            return lhs.name < rhs.name
        }

        // --- Derived lipid insights ---
        func latestLabValue(_ key: String) -> Double? {
            snapshots.first { $0.id == key }?.value
        }
        if let totalCholesterol = latestLabValue("totalcholesterol"),
           let hdl = latestLabValue("hdlcholesterol"), hdl > 0 {
            let ratio = totalCholesterol / hdl
            let ratioText = String(format: "%.1f", ratio)
            if ratio >= 5 {
                findings.append(Finding(
                    severity: .attention,
                    category: .labs,
                    title: "Cholesterol ratio is high",
                    detail: "Your total-to-HDL cholesterol ratio is \(ratioText) (target below 5, ideal below 3.5). This ratio is a useful indicator of cardiovascular risk.",
                    recommendation: "Discuss lipid management with your doctor."
                ))
            } else {
                findings.append(Finding(
                    severity: .info,
                    category: .labs,
                    title: "Cholesterol ratio: \(ratioText)",
                    detail: ratio < 3.5
                        ? "A total-to-HDL cholesterol ratio below 3.5 is considered ideal."
                        : "Your total-to-HDL cholesterol ratio is within the generally recommended target of below 5.",
                    recommendation: nil
                ))
            }
            let nonHDL = totalCholesterol - hdl
            if nonHDL >= 160 {
                findings.append(Finding(
                    severity: .attention,
                    category: .labs,
                    title: "Non-HDL cholesterol is high",
                    detail: "Non-HDL cholesterol (total minus HDL) is \(Int(nonHDL)) mg/dL; below 130 mg/dL is generally recommended. It captures all cholesterol carried by potentially artery-clogging particles.",
                    recommendation: "Worth reviewing with your doctor alongside your full lipid panel."
                ))
            }
        }

        // --- Vitals ---
        func latestVital(_ type: VitalType) -> VitalSample? {
            vitals.filter { $0.type == type }.max { $0.date < $1.date }
        }

        if let bp = latestVital(.bloodPressure), let diastolic = bp.secondaryValue {
            let category = bloodPressureCategory(systolic: bp.value, diastolic: diastolic)
            let reading = "\(Int(bp.value))/\(Int(diastolic)) mmHg"
            switch category {
            case .crisis:
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: "Blood pressure at crisis level",
                    detail: "Latest reading \(reading) falls in the \(category.displayName) category.",
                    recommendation: "Readings this high need prompt medical attention. If it persists on re-measurement, seek care immediately."
                ))
            case .stage2:
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Blood pressure in Stage 2 hypertension range",
                    detail: "Latest reading \(reading) falls in the \(category.displayName) category.",
                    recommendation: "Schedule a visit with your doctor to discuss blood pressure management."
                ))
            case .stage1:
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Blood pressure in Stage 1 hypertension range",
                    detail: "Latest reading \(reading) falls in the \(category.displayName) category.",
                    recommendation: "Recheck regularly and mention it at your next appointment."
                ))
            case .elevated:
                findings.append(Finding(
                    severity: .info,
                    category: .vitals,
                    title: "Blood pressure slightly elevated",
                    detail: "Latest reading \(reading) is above normal but below hypertension thresholds.",
                    recommendation: "Lifestyle measures like exercise and reduced sodium can help."
                ))
            case .normal:
                findings.append(Finding(
                    severity: .info,
                    category: .vitals,
                    title: "Blood pressure is normal",
                    detail: "Latest reading \(reading) is in the normal range.",
                    recommendation: nil
                ))
            }
        }

        if let weight = latestVital(.weight),
           let heightCm = profile?.heightCm,
           let bmiValue = bmi(weightKg: weight.value, heightCm: heightCm) {
            let (name, severity) = bmiCategory(bmiValue)
            findings.append(Finding(
                severity: severity,
                category: .vitals,
                title: "BMI: \(bmiValue.compactFormatted) (\(name))",
                detail: "Based on your latest weight of \(Units.formatted(weight.value, for: .weight)) and height of \(heightCm.compactFormatted) cm.",
                recommendation: severity == .attention ? "Consider discussing weight management with your doctor." : nil
            ))
        }

        if let heartRate = latestVital(.heartRate) {
            if heartRate.value < 50 || heartRate.value > 100 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Resting heart rate \(heartRate.value < 50 ? "low" : "high")",
                    detail: "Latest reading \(Int(heartRate.value)) bpm is outside the typical resting range of 50–100 bpm.",
                    recommendation: "If this persists or comes with symptoms, mention it to your doctor."
                ))
            }
        }

        if let glucose = latestVital(.bloodGlucose) {
            let reading = Units.formatted(glucose.value, for: .bloodGlucose)
            if glucose.value >= 250 || glucose.value < 54 {
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: "Blood glucose at a critical level",
                    detail: "Latest reading \(reading) is far outside the safe range.",
                    recommendation: "Contact your healthcare provider promptly."
                ))
            } else if glucose.value < 70 || glucose.value > 180 {
                let band = Units.displayRange(70...180, for: .bloodGlucose)
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Blood glucose out of range",
                    detail: "Latest reading \(reading) is outside the typical range of \(band.lowerBound.compactFormatted)–\(band.upperBound.compactFormatted) \(Units.label(for: .bloodGlucose)).",
                    recommendation: "Track further readings and discuss them with your doctor."
                ))
            }
        }

        if let spo2 = latestVital(.oxygenSaturation) {
            if spo2.value < 90 {
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: "Oxygen saturation is very low",
                    detail: "Latest reading \(spo2.value.compactFormatted)% is below 90%.",
                    recommendation: "Values below 90% warrant prompt medical evaluation."
                ))
            } else if spo2.value < 95 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Oxygen saturation slightly low",
                    detail: "Latest reading \(spo2.value.compactFormatted)% is below the typical 95–100% range.",
                    recommendation: "Re-measure at rest; mention persistent low readings to your doctor."
                ))
            }
        }

        if let temperature = latestVital(.temperature) {
            let reading = Units.formatted(temperature.value, for: .temperature)
            if temperature.value >= 39.5 || temperature.value < 35 {
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: temperature.value >= 39.5 ? "High fever recorded" : "Very low body temperature recorded",
                    detail: "Latest reading \(reading).",
                    recommendation: "Seek medical advice if this reading is current."
                ))
            } else if temperature.value >= 38 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Fever recorded",
                    detail: "Latest reading \(reading) is above the normal range.",
                    recommendation: "Rest, hydrate, and consult a doctor if the fever persists."
                ))
            }
        }

        if let respiratory = latestVital(.respiratoryRate) {
            if respiratory.value < 12 || respiratory.value > 20 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Respiratory rate \(respiratory.value < 12 ? "low" : "high")",
                    detail: "Latest reading \(respiratory.value.compactFormatted) breaths/min is outside the typical resting range of 12–20.",
                    recommendation: "Re-measure at rest; mention persistent abnormal readings to your doctor."
                ))
            }
        }

        if let sleep = latestVital(.sleepHours) {
            if sleep.value < 6 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: "Short sleep duration",
                    detail: "Latest entry \(sleep.value.compactFormatted) hours is below the recommended 7–9 hours for adults. Chronic short sleep affects blood pressure, glucose regulation, and mood.",
                    recommendation: "Aim for a consistent sleep schedule; discuss persistent sleep problems with your doctor."
                ))
            } else if sleep.value > 10 {
                findings.append(Finding(
                    severity: .info,
                    category: .vitals,
                    title: "Long sleep duration",
                    detail: "Latest entry \(sleep.value.compactFormatted) hours is above the typical 7–9 hour range.",
                    recommendation: "Occasional long sleep is normal; consistently needing 10+ hours is worth mentioning at a checkup."
                ))
            }
        }

        // --- Vital trends ---
        for type in VitalType.allCases {
            let samples = vitals.filter { $0.type == type }.sorted { $0.date < $1.date }
            guard samples.count >= 3 else { continue }
            let series = samples.map { (date: $0.date, value: $0.value) }
            guard let (direction, percentChange) = trend(points: series, range: type.healthyRange) else { continue }
            let changeText = String(format: "%+.0f%%", percentChange)
            let detail: String
            switch direction {
            case .improving:
                detail = "\(type.displayName) changed \(changeText) over \(samples.count) readings and is moving toward its healthy range."
            case .worsening:
                detail = "\(type.displayName) changed \(changeText) over \(samples.count) readings and is moving away from its healthy range."
            case .stable:
                detail = "\(type.displayName) is stable across \(samples.count) readings."
            case .rising, .falling:
                detail = "\(type.displayName) changed \(changeText) over \(samples.count) readings."
            }
            trends.append(TrendInsight(
                metricName: type.displayName,
                unit: type.unit,
                direction: direction,
                percentChange: percentChange,
                pointCount: samples.count,
                detail: detail
            ))
            if direction == .worsening {
                findings.append(Finding(
                    severity: .attention,
                    category: .trends,
                    title: "\(type.displayName) is trending away from its healthy range",
                    detail: detail,
                    recommendation: "Keep tracking this value and mention the trend to your doctor."
                ))
            }
        }

        // --- Medications ---
        let activeMedications = medications.filter(\.isActive)
        if !activeMedications.isEmpty {
            let names = activeMedications.map(\.name).joined(separator: ", ")
            findings.append(Finding(
                severity: .info,
                category: .medications,
                title: "\(activeMedications.count) active medication\(activeMedications.count == 1 ? "" : "s")",
                detail: "Currently tracking: \(names).",
                recommendation: "Review your medication list with your doctor periodically."
            ))

            // Educational drug-interaction check across active medications.
            for interaction in MedicationInteractions.check(medicationNames: activeMedications.map(\.name)) {
                findings.append(Finding(
                    severity: interaction.severity == .major ? .attention : .info,
                    category: .medications,
                    title: "\(interaction.severity.displayName) interaction: \(interaction.drugA) + \(interaction.drugB)",
                    detail: interaction.explanation,
                    recommendation: interaction.recommendation
                ))
            }
        }

        // --- Symptoms ---
        let recentSymptoms = symptoms.filter { $0.date >= now.addingTimeInterval(-14 * 86_400) }
        if let severe = recentSymptoms.filter({ $0.severity >= 8 }).max(by: { $0.date < $1.date }) {
            findings.append(Finding(
                severity: .attention,
                category: .general,
                title: "Severe symptom logged: \(severe.name)",
                detail: "You rated \(severe.name.lowercased()) at \(severe.severity)/10 on \(severe.date.formatted(date: .abbreviated, time: .omitted)).",
                recommendation: "If this symptom persists or worsens, contact your healthcare provider."
            ))
        } else if recentSymptoms.count >= 3 {
            let names = Array(Set(recentSymptoms.map(\.name))).sorted().joined(separator: ", ")
            findings.append(Finding(
                severity: .info,
                category: .general,
                title: "\(recentSymptoms.count) symptoms logged in the last two weeks",
                detail: "Logged: \(names).",
                recommendation: "Bring your symptom journal to your next appointment — patterns help your doctor."
            ))
        }

        // --- Appointments ---
        if let next = appointments.filter({ $0.date > now }).min(by: { $0.date < $1.date }) {
            let doctorText = next.doctor.isEmpty ? "" : " with \(next.doctor)"
            findings.append(Finding(
                severity: .info,
                category: .general,
                title: "Upcoming: \(next.title)",
                detail: "Scheduled for \(next.date.formatted(date: .abbreviated, time: .shortened))\(doctorText).",
                recommendation: nil
            ))
        }

        // --- Data gaps ---
        let hasData = !allResults.isEmpty || !vitals.isEmpty
        if hasData {
            if let lastReportDate = reports.map(\.date).max(),
               lastReportDate < now.addingTimeInterval(-365 * 86_400) {
                findings.append(Finding(
                    severity: .info,
                    category: .general,
                    title: "No recent medical reports",
                    detail: "Your most recent report is from \(lastReportDate.formatted(date: .abbreviated, time: .omitted)) — over a year ago.",
                    recommendation: "Consider scheduling a routine checkup."
                ))
            }
            if profile == nil || profile?.heightCm == nil {
                findings.append(Finding(
                    severity: .info,
                    category: .general,
                    title: "Complete your health profile",
                    detail: "Adding your height, date of birth, and biological sex enables BMI and sex-specific reference ranges.",
                    recommendation: "Fill in your profile under More → Profile."
                ))
            }
        }

        // --- Score ---
        findings.sort { $0.severity > $1.severity }
        trends.sort { $0.direction.isConcern && !$1.direction.isConcern }

        let criticalCount = findings.filter { $0.severity == .critical }.count
        let attentionCount = findings.filter { $0.severity == .attention }.count
        let worseningCount = trends.filter { $0.direction == .worsening }.count

        var score = 100 - 18 * criticalCount - 7 * attentionCount - 3 * worseningCount
        score = min(100, max(5, score))
        if !hasData { score = 0 }

        // --- Summary ---
        var summaryParts: [String] = []
        if hasData {
            var counted: [String] = []
            if !allResults.isEmpty {
                counted.append("\(allResults.count) lab result\(allResults.count == 1 ? "" : "s") from \(reports.count) report\(reports.count == 1 ? "" : "s")")
            }
            if !vitals.isEmpty {
                counted.append("\(vitals.count) vital reading\(vitals.count == 1 ? "" : "s")")
            }
            if !medications.isEmpty {
                counted.append("\(medications.count) medication\(medications.count == 1 ? "" : "s")")
            }
            summaryParts.append("Reviewed " + counted.joined(separator: ", ") + ".")

            if criticalCount > 0 {
                summaryParts.append("\(criticalCount) item\(criticalCount == 1 ? " is" : "s are") at a critical level — please contact your healthcare provider promptly.")
            } else if attentionCount > 0 {
                summaryParts.append("\(attentionCount) item\(attentionCount == 1 ? " is" : "s are") outside typical ranges and worth discussing at your next visit.")
            } else {
                summaryParts.append("All tracked values are within their typical ranges.")
            }
            if worseningCount > 0 {
                summaryParts.append("\(worseningCount) metric\(worseningCount == 1 ? " is" : "s are") trending in a direction worth watching.")
            }
        } else {
            summaryParts.append("Add medical reports, lab results, or vitals to generate your first health review.")
        }

        return HealthReview(
            generatedAt: now,
            hasData: hasData,
            score: score,
            summary: summaryParts.joined(separator: " "),
            findings: findings,
            trends: trends,
            labSnapshots: snapshots
        )
    }
}
