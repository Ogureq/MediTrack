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
        case .info: String(localized: "severity.info", defaultValue: "Informational", table: "Engine")
        case .attention: String(localized: "severity.attention", defaultValue: "Needs Attention", table: "Engine")
        case .critical: String(localized: "severity.critical", defaultValue: "Critical", table: "Engine")
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
        case .criticalLow: String(localized: "labStatus.criticalLow", defaultValue: "Critical Low", table: "Engine")
        case .low: String(localized: "labStatus.low", defaultValue: "Low", table: "Engine")
        case .normal: String(localized: "labStatus.normal", defaultValue: "In Range", table: "Engine")
        case .high: String(localized: "labStatus.high", defaultValue: "High", table: "Engine")
        case .criticalHigh: String(localized: "labStatus.criticalHigh", defaultValue: "Critical High", table: "Engine")
        case .unknown: String(localized: "labStatus.unknown", defaultValue: "No Range", table: "Engine")
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
        case .improving: String(localized: "trend.improving", defaultValue: "Improving", table: "Engine")
        case .worsening: String(localized: "trend.worsening", defaultValue: "Worsening", table: "Engine")
        case .stable: String(localized: "trend.stable", defaultValue: "Stable", table: "Engine")
        case .rising: String(localized: "trend.rising", defaultValue: "Rising", table: "Engine")
        case .falling: String(localized: "trend.falling", defaultValue: "Falling", table: "Engine")
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
        case .normal: String(localized: "bp.normal", defaultValue: "Normal", table: "Engine")
        case .elevated: String(localized: "bp.elevated", defaultValue: "Elevated", table: "Engine")
        case .stage1: String(localized: "bp.stage1", defaultValue: "Hypertension Stage 1", table: "Engine")
        case .stage2: String(localized: "bp.stage2", defaultValue: "Hypertension Stage 2", table: "Engine")
        case .crisis: String(localized: "bp.crisis", defaultValue: "Hypertensive Crisis", table: "Engine")
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

    static var disclaimer: String {
        String(
            localized: "review.disclaimer",
            defaultValue: """
                Gemocode provides educational information only. It is not a medical device, does not \
                provide a diagnosis, and is not a substitute for professional medical advice. Always \
                consult a qualified healthcare professional about your results and before making any \
                health decisions.
                """,
            table: "Engine"
        )
    }

    var criticalFindings: [Finding] { findings.filter { $0.severity == .critical } }
    var attentionFindings: [Finding] { findings.filter { $0.severity == .attention } }
    var infoFindings: [Finding] { findings.filter { $0.severity == .info } }

    var scoreLabel: String {
        switch score {
        case 90...100: String(localized: "score.excellent", defaultValue: "Excellent", table: "Engine")
        case 75..<90: String(localized: "score.good", defaultValue: "Good", table: "Engine")
        case 60..<75: String(localized: "score.fair", defaultValue: "Fair", table: "Engine")
        case 40..<60: String(localized: "score.needsAttention", defaultValue: "Needs Attention", table: "Engine")
        default: String(localized: "score.talkToDoctor", defaultValue: "Talk to Your Doctor", table: "Engine")
        }
    }

    var shareText: String {
        var lines: [String] = []
        lines.append(String(
            format: String(localized: "share.title", defaultValue: "Gemocode Health Review — %@", table: "Engine"),
            generatedAt.formatted(date: .abbreviated, time: .shortened)
        ))
        lines.append(String(
            format: String(localized: "share.overallScore", defaultValue: "Overall score: %1$lld/100 (%2$@)", table: "Engine"),
            Int64(score), scoreLabel
        ))
        lines.append("")
        lines.append(summary)
        for severity in [Severity.critical, .attention, .info] {
            let group = findings.filter { $0.severity == severity }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append(severity.displayName.uppercased())
            for finding in group {
                lines.append(String(
                    format: String(localized: "share.bulletFinding", defaultValue: "• %1$@: %2$@", table: "Engine"),
                    finding.title, finding.detail
                ))
                if let recommendation = finding.recommendation {
                    lines.append(String(
                        format: String(localized: "share.bulletRecommendation", defaultValue: "  → %@", table: "Engine"),
                        recommendation
                    ))
                }
            }
        }
        if !trends.isEmpty {
            lines.append("")
            lines.append(String(localized: "share.trendsHeader", defaultValue: "TRENDS", table: "Engine"))
            for trend in trends {
                lines.append(String(
                    format: String(localized: "share.bulletTrend", defaultValue: "• %@", table: "Engine"),
                    trend.detail
                ))
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
        case ..<18.5: (String(localized: "bmi.underweight", defaultValue: "Underweight", table: "Engine"), .attention)
        case 18.5..<25: (String(localized: "bmi.normal", defaultValue: "Normal weight", table: "Engine"), .info)
        case 25..<30: (String(localized: "bmi.overweight", defaultValue: "Overweight", table: "Engine"), .info)
        default: (String(localized: "bmi.obese", defaultValue: "Obese", table: "Engine"), .attention)
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

            let noReferenceRangeText = String(localized: "lab.noReferenceRange", defaultValue: "no reference range", table: "Engine")
            let rangeText = range.map { "\($0.lowerBound.compactFormatted)–\($0.upperBound.compactFormatted) \(latest.unit)" } ?? noReferenceRangeText
            let valueText = "\(latest.value.compactFormatted) \(latest.unit)"

            switch labStatus {
            case .criticalLow, .criticalHigh:
                let meaning = labStatus == .criticalLow ? reference?.lowMeaning : reference?.highMeaning
                findings.append(Finding(
                    severity: .critical,
                    category: .labs,
                    title: String(
                        format: String(localized: "finding.lab.critical.title", defaultValue: "%@ is at a critical level", table: "Engine"),
                        latest.displayName
                    ),
                    detail: String(
                        format: String(localized: "finding.lab.detail", defaultValue: "Latest value %1$@ (typical range %2$@). %3$@", table: "Engine"),
                        valueText, rangeText, meaning ?? ""
                    ),
                    recommendation: String(localized: "finding.lab.critical.recommendation", defaultValue: "Contact your healthcare provider promptly to review this result.", table: "Engine")
                ))
            case .low, .high:
                let meaning = labStatus == .low ? reference?.lowMeaning : reference?.highMeaning
                let titleFormat = labStatus == .low
                    ? String(localized: "finding.lab.low.title", defaultValue: "%@ is below its reference range", table: "Engine")
                    : String(localized: "finding.lab.high.title", defaultValue: "%@ is above its reference range", table: "Engine")
                findings.append(Finding(
                    severity: .attention,
                    category: .labs,
                    title: String(format: titleFormat, latest.displayName),
                    detail: String(
                        format: String(localized: "finding.lab.detail", defaultValue: "Latest value %1$@ (typical range %2$@). %3$@", table: "Engine"),
                        valueText, rangeText, meaning ?? ""
                    ),
                    recommendation: String(localized: "finding.lab.attention.recommendation", defaultValue: "Worth discussing with your doctor at your next visit.", table: "Engine")
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
                    detail = String(
                        format: String(localized: "trend.lab.improving", defaultValue: "%1$@ changed %2$@ over %3$lld entries and is moving toward its reference range.", table: "Engine"),
                        latest.displayName, changeText, Int64(sorted.count)
                    )
                case .worsening:
                    detail = String(
                        format: String(localized: "trend.lab.worsening", defaultValue: "%1$@ changed %2$@ over %3$lld entries and is moving away from its reference range.", table: "Engine"),
                        latest.displayName, changeText, Int64(sorted.count)
                    )
                case .stable:
                    detail = String(
                        format: String(localized: "trend.lab.stable", defaultValue: "%1$@ is stable across %2$lld entries.", table: "Engine"),
                        latest.displayName, Int64(sorted.count)
                    )
                case .rising, .falling:
                    detail = String(
                        format: String(localized: "trend.lab.risingFalling", defaultValue: "%1$@ changed %2$@ over %3$lld entries.", table: "Engine"),
                        latest.displayName, changeText, Int64(sorted.count)
                    )
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
                        title: String(
                            format: String(localized: "finding.trend.lab.worsening.title", defaultValue: "%@ is trending away from its range", table: "Engine"),
                            latest.displayName
                        ),
                        detail: detail,
                        recommendation: String(localized: "finding.trend.recommendation", defaultValue: "Keep tracking this value and mention the trend to your doctor.", table: "Engine")
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
                    title: String(localized: "finding.cholesterolRatio.high.title", defaultValue: "Cholesterol ratio is high", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.cholesterolRatio.high.detail", defaultValue: "Your total-to-HDL cholesterol ratio is %@ (target below 5, ideal below 3.5). This ratio is a useful indicator of cardiovascular risk.", table: "Engine"),
                        ratioText
                    ),
                    recommendation: String(localized: "finding.cholesterolRatio.high.recommendation", defaultValue: "Discuss lipid management with your doctor.", table: "Engine")
                ))
            } else {
                findings.append(Finding(
                    severity: .info,
                    category: .labs,
                    title: String(
                        format: String(localized: "finding.cholesterolRatio.normal.title", defaultValue: "Cholesterol ratio: %@", table: "Engine"),
                        ratioText
                    ),
                    detail: ratio < 3.5
                        ? String(localized: "finding.cholesterolRatio.ideal.detail", defaultValue: "A total-to-HDL cholesterol ratio below 3.5 is considered ideal.", table: "Engine")
                        : String(localized: "finding.cholesterolRatio.withinTarget.detail", defaultValue: "Your total-to-HDL cholesterol ratio is within the generally recommended target of below 5.", table: "Engine"),
                    recommendation: nil
                ))
            }
            let nonHDL = totalCholesterol - hdl
            if nonHDL >= 160 {
                findings.append(Finding(
                    severity: .attention,
                    category: .labs,
                    title: String(localized: "finding.nonHDL.title", defaultValue: "Non-HDL cholesterol is high", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.nonHDL.detail", defaultValue: "Non-HDL cholesterol (total minus HDL) is %lld mg/dL; below 130 mg/dL is generally recommended. It captures all cholesterol carried by potentially artery-clogging particles.", table: "Engine"),
                        Int64(nonHDL)
                    ),
                    recommendation: String(localized: "finding.nonHDL.recommendation", defaultValue: "Worth reviewing with your doctor alongside your full lipid panel.", table: "Engine")
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
            let bpDetailFormat = String(localized: "finding.bp.detail", defaultValue: "Latest reading %1$@ falls in the %2$@ category.", table: "Engine")
            switch category {
            case .crisis:
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: String(localized: "finding.bp.crisis.title", defaultValue: "Blood pressure at crisis level", table: "Engine"),
                    detail: String(format: bpDetailFormat, reading, category.displayName),
                    recommendation: String(localized: "finding.bp.crisis.recommendation", defaultValue: "Readings this high need prompt medical attention. If it persists on re-measurement, seek care immediately.", table: "Engine")
                ))
            case .stage2:
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: String(localized: "finding.bp.stage2.title", defaultValue: "Blood pressure in Stage 2 hypertension range", table: "Engine"),
                    detail: String(format: bpDetailFormat, reading, category.displayName),
                    recommendation: String(localized: "finding.bp.stage2.recommendation", defaultValue: "Schedule a visit with your doctor to discuss blood pressure management.", table: "Engine")
                ))
            case .stage1:
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: String(localized: "finding.bp.stage1.title", defaultValue: "Blood pressure in Stage 1 hypertension range", table: "Engine"),
                    detail: String(format: bpDetailFormat, reading, category.displayName),
                    recommendation: String(localized: "finding.bp.stage1.recommendation", defaultValue: "Recheck regularly and mention it at your next appointment.", table: "Engine")
                ))
            case .elevated:
                findings.append(Finding(
                    severity: .info,
                    category: .vitals,
                    title: String(localized: "finding.bp.elevated.title", defaultValue: "Blood pressure slightly elevated", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.bp.elevated.detail", defaultValue: "Latest reading %@ is above normal but below hypertension thresholds.", table: "Engine"),
                        reading
                    ),
                    recommendation: String(localized: "finding.bp.elevated.recommendation", defaultValue: "Lifestyle measures like exercise and reduced sodium can help.", table: "Engine")
                ))
            case .normal:
                findings.append(Finding(
                    severity: .info,
                    category: .vitals,
                    title: String(localized: "finding.bp.normal.title", defaultValue: "Blood pressure is normal", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.bp.normal.detail", defaultValue: "Latest reading %@ is in the normal range.", table: "Engine"),
                        reading
                    ),
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
                title: String(
                    format: String(localized: "finding.bmi.title", defaultValue: "BMI: %1$@ (%2$@)", table: "Engine"),
                    bmiValue.compactFormatted, name
                ),
                detail: String(
                    format: String(localized: "finding.bmi.detail", defaultValue: "Based on your latest weight of %1$@ and height of %2$@ cm.", table: "Engine"),
                    Units.formatted(weight.value, for: .weight), heightCm.compactFormatted
                ),
                recommendation: severity == .attention
                    ? String(localized: "finding.bmi.recommendation", defaultValue: "Consider discussing weight management with your doctor.", table: "Engine")
                    : nil
            ))
        }

        if let heartRate = latestVital(.heartRate) {
            if heartRate.value < 50 || heartRate.value > 100 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: heartRate.value < 50
                        ? String(localized: "finding.heartRate.low.title", defaultValue: "Resting heart rate low", table: "Engine")
                        : String(localized: "finding.heartRate.high.title", defaultValue: "Resting heart rate high", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.heartRate.detail", defaultValue: "Latest reading %lld bpm is outside the typical resting range of 50–100 bpm.", table: "Engine"),
                        Int64(heartRate.value)
                    ),
                    recommendation: String(localized: "finding.heartRate.recommendation", defaultValue: "If this persists or comes with symptoms, mention it to your doctor.", table: "Engine")
                ))
            }
        }

        if let glucose = latestVital(.bloodGlucose) {
            let reading = Units.formatted(glucose.value, for: .bloodGlucose)
            if glucose.value >= 250 || glucose.value < 54 {
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: String(localized: "finding.glucose.critical.title", defaultValue: "Blood glucose at a critical level", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.glucose.critical.detail", defaultValue: "Latest reading %@ is far outside the safe range.", table: "Engine"),
                        reading
                    ),
                    recommendation: String(localized: "finding.glucose.critical.recommendation", defaultValue: "Contact your healthcare provider promptly.", table: "Engine")
                ))
            } else if glucose.value < 70 || glucose.value > 180 {
                let band = Units.displayRange(70...180, for: .bloodGlucose)
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: String(localized: "finding.glucose.attention.title", defaultValue: "Blood glucose out of range", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.glucose.attention.detail", defaultValue: "Latest reading %1$@ is outside the typical range of %2$@–%3$@ %4$@.", table: "Engine"),
                        reading, band.lowerBound.compactFormatted, band.upperBound.compactFormatted, Units.label(for: .bloodGlucose)
                    ),
                    recommendation: String(localized: "finding.glucose.attention.recommendation", defaultValue: "Track further readings and discuss them with your doctor.", table: "Engine")
                ))
            }
        }

        if let spo2 = latestVital(.oxygenSaturation) {
            if spo2.value < 90 {
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: String(localized: "finding.spo2.critical.title", defaultValue: "Oxygen saturation is very low", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.spo2.critical.detail", defaultValue: "Latest reading %@%% is below 90%%.", table: "Engine"),
                        spo2.value.compactFormatted
                    ),
                    recommendation: String(localized: "finding.spo2.critical.recommendation", defaultValue: "Values below 90% warrant prompt medical evaluation.", table: "Engine")
                ))
            } else if spo2.value < 95 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: String(localized: "finding.spo2.attention.title", defaultValue: "Oxygen saturation slightly low", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.spo2.attention.detail", defaultValue: "Latest reading %@%% is below the typical 95–100%% range.", table: "Engine"),
                        spo2.value.compactFormatted
                    ),
                    recommendation: String(localized: "finding.spo2.attention.recommendation", defaultValue: "Re-measure at rest; mention persistent low readings to your doctor.", table: "Engine")
                ))
            }
        }

        if let temperature = latestVital(.temperature) {
            let reading = Units.formatted(temperature.value, for: .temperature)
            if temperature.value >= 39.5 || temperature.value < 35 {
                findings.append(Finding(
                    severity: .critical,
                    category: .vitals,
                    title: temperature.value >= 39.5
                        ? String(localized: "finding.temp.highFever.title", defaultValue: "High fever recorded", table: "Engine")
                        : String(localized: "finding.temp.lowTemp.title", defaultValue: "Very low body temperature recorded", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.temp.critical.detail", defaultValue: "Latest reading %@.", table: "Engine"),
                        reading
                    ),
                    recommendation: String(localized: "finding.temp.critical.recommendation", defaultValue: "Seek medical advice if this reading is current.", table: "Engine")
                ))
            } else if temperature.value >= 38 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: String(localized: "finding.temp.fever.title", defaultValue: "Fever recorded", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.temp.fever.detail", defaultValue: "Latest reading %@ is above the normal range.", table: "Engine"),
                        reading
                    ),
                    recommendation: String(localized: "finding.temp.fever.recommendation", defaultValue: "Rest, hydrate, and consult a doctor if the fever persists.", table: "Engine")
                ))
            }
        }

        if let respiratory = latestVital(.respiratoryRate) {
            if respiratory.value < 12 || respiratory.value > 20 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: respiratory.value < 12
                        ? String(localized: "finding.resp.low.title", defaultValue: "Respiratory rate low", table: "Engine")
                        : String(localized: "finding.resp.high.title", defaultValue: "Respiratory rate high", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.resp.detail", defaultValue: "Latest reading %@ breaths/min is outside the typical resting range of 12–20.", table: "Engine"),
                        respiratory.value.compactFormatted
                    ),
                    recommendation: String(localized: "finding.resp.recommendation", defaultValue: "Re-measure at rest; mention persistent abnormal readings to your doctor.", table: "Engine")
                ))
            }
        }

        if let sleep = latestVital(.sleepHours) {
            if sleep.value < 6 {
                findings.append(Finding(
                    severity: .attention,
                    category: .vitals,
                    title: String(localized: "finding.sleep.short.title", defaultValue: "Short sleep duration", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.sleep.short.detail", defaultValue: "Latest entry %@ hours is below the recommended 7–9 hours for adults. Chronic short sleep affects blood pressure, glucose regulation, and mood.", table: "Engine"),
                        sleep.value.compactFormatted
                    ),
                    recommendation: String(localized: "finding.sleep.short.recommendation", defaultValue: "Aim for a consistent sleep schedule; discuss persistent sleep problems with your doctor.", table: "Engine")
                ))
            } else if sleep.value > 10 {
                findings.append(Finding(
                    severity: .info,
                    category: .vitals,
                    title: String(localized: "finding.sleep.long.title", defaultValue: "Long sleep duration", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.sleep.long.detail", defaultValue: "Latest entry %@ hours is above the typical 7–9 hour range.", table: "Engine"),
                        sleep.value.compactFormatted
                    ),
                    recommendation: String(localized: "finding.sleep.long.recommendation", defaultValue: "Occasional long sleep is normal; consistently needing 10+ hours is worth mentioning at a checkup.", table: "Engine")
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
                detail = String(
                    format: String(localized: "trend.vital.improving", defaultValue: "%1$@ changed %2$@ over %3$lld readings and is moving toward its healthy range.", table: "Engine"),
                    type.displayName, changeText, Int64(samples.count)
                )
            case .worsening:
                detail = String(
                    format: String(localized: "trend.vital.worsening", defaultValue: "%1$@ changed %2$@ over %3$lld readings and is moving away from its healthy range.", table: "Engine"),
                    type.displayName, changeText, Int64(samples.count)
                )
            case .stable:
                detail = String(
                    format: String(localized: "trend.vital.stable", defaultValue: "%1$@ is stable across %2$lld readings.", table: "Engine"),
                    type.displayName, Int64(samples.count)
                )
            case .rising, .falling:
                detail = String(
                    format: String(localized: "trend.vital.risingFalling", defaultValue: "%1$@ changed %2$@ over %3$lld readings.", table: "Engine"),
                    type.displayName, changeText, Int64(samples.count)
                )
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
                    title: String(
                        format: String(localized: "finding.trend.vital.worsening.title", defaultValue: "%@ is trending away from its healthy range", table: "Engine"),
                        type.displayName
                    ),
                    detail: detail,
                    recommendation: String(localized: "finding.trend.recommendation", defaultValue: "Keep tracking this value and mention the trend to your doctor.", table: "Engine")
                ))
            }
        }

        // --- Medications ---
        let activeMedications = medications.filter(\.isActive)
        if !activeMedications.isEmpty {
            let names = activeMedications.map(\.name).joined(separator: ", ")
            let medicationsTitle = activeMedications.count == 1
                ? String(localized: "finding.medications.title.one", defaultValue: "1 active medication", table: "Engine")
                : String(
                    format: String(localized: "finding.medications.title.many", defaultValue: "%lld active medications", table: "Engine"),
                    Int64(activeMedications.count)
                )
            findings.append(Finding(
                severity: .info,
                category: .medications,
                title: medicationsTitle,
                detail: String(
                    format: String(localized: "finding.medications.detail", defaultValue: "Currently tracking: %@.", table: "Engine"),
                    names
                ),
                recommendation: String(localized: "finding.medications.recommendation", defaultValue: "Review your medication list with your doctor periodically.", table: "Engine")
            ))

            // Educational drug-interaction check across active medications.
            for interaction in MedicationInteractions.check(medicationNames: activeMedications.map(\.name)) {
                findings.append(Finding(
                    severity: interaction.severity == .major ? .attention : .info,
                    category: .medications,
                    title: String(
                        format: String(localized: "finding.medications.interaction.title", defaultValue: "%1$@ interaction: %2$@ + %3$@", table: "Engine"),
                        interaction.severity.displayName, interaction.drugA, interaction.drugB
                    ),
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
                title: String(
                    format: String(localized: "finding.symptom.severe.title", defaultValue: "Severe symptom logged: %@", table: "Engine"),
                    severe.name
                ),
                detail: String(
                    format: String(localized: "finding.symptom.severe.detail", defaultValue: "You rated %1$@ at %2$lld/10 on %3$@.", table: "Engine"),
                    severe.name.lowercased(), Int64(severe.severity), severe.date.formatted(date: .abbreviated, time: .omitted)
                ),
                recommendation: String(localized: "finding.symptom.severe.recommendation", defaultValue: "If this symptom persists or worsens, contact your healthcare provider.", table: "Engine")
            ))
        } else if recentSymptoms.count >= 3 {
            let names = Array(Set(recentSymptoms.map(\.name))).sorted().joined(separator: ", ")
            findings.append(Finding(
                severity: .info,
                category: .general,
                title: String(
                    format: String(localized: "finding.symptom.multiple.title", defaultValue: "%lld symptoms logged in the last two weeks", table: "Engine"),
                    Int64(recentSymptoms.count)
                ),
                detail: String(
                    format: String(localized: "finding.symptom.multiple.detail", defaultValue: "Logged: %@.", table: "Engine"),
                    names
                ),
                recommendation: String(localized: "finding.symptom.multiple.recommendation", defaultValue: "Bring your symptom journal to your next appointment — patterns help your doctor.", table: "Engine")
            ))
        }

        // --- Appointments ---
        if let next = appointments.filter({ $0.date > now }).min(by: { $0.date < $1.date }) {
            let doctorText = next.doctor.isEmpty
                ? ""
                : String(format: String(localized: "finding.appointment.withDoctor", defaultValue: " with %@", table: "Engine"), next.doctor)
            findings.append(Finding(
                severity: .info,
                category: .general,
                title: String(
                    format: String(localized: "finding.appointment.title", defaultValue: "Upcoming: %@", table: "Engine"),
                    next.title
                ),
                detail: String(
                    format: String(localized: "finding.appointment.detail", defaultValue: "Scheduled for %1$@%2$@.", table: "Engine"),
                    next.date.formatted(date: .abbreviated, time: .shortened), doctorText
                ),
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
                    title: String(localized: "finding.noRecentReports.title", defaultValue: "No recent medical reports", table: "Engine"),
                    detail: String(
                        format: String(localized: "finding.noRecentReports.detail", defaultValue: "Your most recent report is from %@ — over a year ago.", table: "Engine"),
                        lastReportDate.formatted(date: .abbreviated, time: .omitted)
                    ),
                    recommendation: String(localized: "finding.noRecentReports.recommendation", defaultValue: "Consider scheduling a routine checkup.", table: "Engine")
                ))
            }
            if profile == nil || profile?.heightCm == nil {
                findings.append(Finding(
                    severity: .info,
                    category: .general,
                    title: String(localized: "finding.completeProfile.title", defaultValue: "Complete your health profile", table: "Engine"),
                    detail: String(localized: "finding.completeProfile.detail", defaultValue: "Adding your height, date of birth, and biological sex enables BMI and sex-specific reference ranges.", table: "Engine"),
                    recommendation: String(localized: "finding.completeProfile.recommendation", defaultValue: "Fill in your profile under More → Profile.", table: "Engine")
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
                let resultPhrase = allResults.count == 1
                    ? String(localized: "summary.labResults.one", defaultValue: "1 lab result", table: "Engine")
                    : String(format: String(localized: "summary.labResults.many", defaultValue: "%lld lab results", table: "Engine"), Int64(allResults.count))
                let reportPhrase = reports.count == 1
                    ? String(localized: "summary.reports.one", defaultValue: "1 report", table: "Engine")
                    : String(format: String(localized: "summary.reports.many", defaultValue: "%lld reports", table: "Engine"), Int64(reports.count))
                counted.append(String(
                    format: String(localized: "summary.labResultsFromReports", defaultValue: "%1$@ from %2$@", table: "Engine"),
                    resultPhrase, reportPhrase
                ))
            }
            if !vitals.isEmpty {
                let phrase = vitals.count == 1
                    ? String(localized: "summary.vitalReadings.one", defaultValue: "1 vital reading", table: "Engine")
                    : String(format: String(localized: "summary.vitalReadings.many", defaultValue: "%lld vital readings", table: "Engine"), Int64(vitals.count))
                counted.append(phrase)
            }
            if !medications.isEmpty {
                let phrase = medications.count == 1
                    ? String(localized: "summary.medications.one", defaultValue: "1 medication", table: "Engine")
                    : String(format: String(localized: "summary.medications.many", defaultValue: "%lld medications", table: "Engine"), Int64(medications.count))
                counted.append(phrase)
            }
            summaryParts.append(String(
                format: String(localized: "summary.reviewed", defaultValue: "Reviewed %@.", table: "Engine"),
                counted.joined(separator: ", ")
            ))

            if criticalCount > 0 {
                summaryParts.append(criticalCount == 1
                    ? String(localized: "summary.criticalItems.one", defaultValue: "1 item is at a critical level — please contact your healthcare provider promptly.", table: "Engine")
                    : String(format: String(localized: "summary.criticalItems.many", defaultValue: "%lld items are at a critical level — please contact your healthcare provider promptly.", table: "Engine"), Int64(criticalCount)))
            } else if attentionCount > 0 {
                summaryParts.append(attentionCount == 1
                    ? String(localized: "summary.attentionItems.one", defaultValue: "1 item is outside typical ranges and worth discussing at your next visit.", table: "Engine")
                    : String(format: String(localized: "summary.attentionItems.many", defaultValue: "%lld items are outside typical ranges and worth discussing at your next visit.", table: "Engine"), Int64(attentionCount)))
            } else {
                summaryParts.append(String(localized: "summary.allNormal", defaultValue: "All tracked values are within their typical ranges.", table: "Engine"))
            }
            if worseningCount > 0 {
                summaryParts.append(worseningCount == 1
                    ? String(localized: "summary.worseningMetrics.one", defaultValue: "1 metric is trending in a direction worth watching.", table: "Engine")
                    : String(format: String(localized: "summary.worseningMetrics.many", defaultValue: "%lld metrics are trending in a direction worth watching.", table: "Engine"), Int64(worseningCount)))
            }
        } else {
            summaryParts.append(String(localized: "summary.noData", defaultValue: "Add medical reports, lab results, or vitals to generate your first health review.", table: "Engine"))
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
