import Foundation

// MARK: - Timeline event

/// The kind of record a `TimelineEvent` originated from.
enum TimelineCategory: String, CaseIterable, Identifiable {
    case report
    case lab
    case vital
    case score
    case medication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .report: "Reports"
        case .lab: "Labs"
        case .vital: "Vitals"
        case .score: "Score"
        case .medication: "Medications"
        }
    }
}

/// How noteworthy an event is, used to color-code timeline rows.
enum TimelineSignificance: Int, Comparable {
    case routine = 0
    case notable = 1
    case important = 2

    static func < (lhs: TimelineSignificance, rhs: TimelineSignificance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One entry in the deterministic, locally-generated health timeline.
/// Captions are template-built from stored data only — no AI involved.
struct TimelineEvent: Identifiable, Equatable {
    let id: String
    let date: Date
    let title: String
    let detail: String
    let category: TimelineCategory
    let significance: TimelineSignificance
    let systemImage: String
}

// MARK: - Timeline generator

/// Pure, deterministic generator that turns stored records into a narrative
/// timeline of notable health changes. Mirrors `AnalysisEngine`'s style:
/// no `Date()` inside, `now` is always passed in, and every caption is a
/// plain string template — nothing here calls out to AI.
enum HealthTimeline {

    /// Default cap on the number of events returned by `events(...)`.
    static let defaultLimit = 100

    /// Window used to evaluate a vital's short-term trend for a
    /// range-crossing event.
    private static let vitalTrendWindow: TimeInterval = 30 * 86_400

    static func events(
        reports: [MedicalReport],
        vitals: [VitalSample],
        scores: [ScoreSnapshot],
        medications: [Medication],
        profile: HealthProfile? = nil,
        now: Date = .now,
        limit: Int = defaultLimit
    ) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let sex = profile?.sex

        events.append(contentsOf: reportEvents(reports: reports))
        events.append(contentsOf: labEvents(reports: reports, sex: sex))
        events.append(contentsOf: scoreEvents(scores: scores))
        events.append(contentsOf: medicationEvents(medications: medications))
        events.append(contentsOf: vitalTrendEvents(vitals: vitals, now: now))

        // Sort newest first; break date ties on id so ordering is fully
        // deterministic regardless of dictionary-grouping iteration order.
        events.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }

        if events.count > limit {
            events.removeLast(events.count - limit)
        }
        return events
    }

    // MARK: Reports

    private static func reportEvents(reports: [MedicalReport]) -> [TimelineEvent] {
        reports.map { report in
            var detailParts: [String] = [report.category.displayName]
            if !report.provider.isEmpty {
                detailParts.append(report.provider)
            } else if !report.facility.isEmpty {
                detailParts.append(report.facility)
            }
            return TimelineEvent(
                id: "report:\(report.title)|\(report.date.timeIntervalSince1970)",
                date: report.date,
                title: report.title.isEmpty ? report.category.displayName : report.title,
                detail: detailParts.joined(separator: " · "),
                category: .report,
                significance: .routine,
                systemImage: report.category.systemImage
            )
        }
    }

    // MARK: Labs

    private static func labEvents(reports: [MedicalReport], sex: BiologicalSex?) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let allResults = reports.flatMap { $0.labResults }
        let grouped = Dictionary(grouping: allResults) { $0.seriesKey }

        for (key, results) in grouped {
            let sorted = results.sorted { $0.date < $1.date }
            guard sorted.count >= 2 else { continue }

            for index in 1..<sorted.count {
                let previous = sorted[index - 1]
                let current = sorted[index]

                let previousStatus = AnalysisEngine.status(
                    value: previous.value,
                    range: previous.referenceRange(for: sex),
                    criticalLow: previous.catalogReference?.criticalLow,
                    criticalHigh: previous.catalogReference?.criticalHigh
                )
                let currentStatus = AnalysisEngine.status(
                    value: current.value,
                    range: current.referenceRange(for: sex),
                    criticalLow: current.catalogReference?.criticalLow,
                    criticalHigh: current.catalogReference?.criticalHigh
                )

                let name = current.displayName
                let unit = current.unit
                let prevText = previous.value.compactFormatted
                let currText = current.value.compactFormatted
                let percentChange = previous.value != 0
                    ? (current.value - previous.value) / abs(previous.value) * 100
                    : 0

                if !previousStatus.isOutOfRange && currentStatus.isOutOfRange {
                    let direction = (currentStatus == .high || currentStatus == .criticalHigh) ? "above" : "below"
                    events.append(TimelineEvent(
                        id: "lab-cross-out:\(key):\(current.date.timeIntervalSince1970)",
                        date: current.date,
                        title: "\(name) moved out of range",
                        detail: "\(name) moved \(direction) its reference range: \(prevText) → \(currText) \(unit)",
                        category: .lab,
                        significance: .important,
                        systemImage: "exclamationmark.triangle.fill"
                    ))
                } else if previousStatus.isOutOfRange && !currentStatus.isOutOfRange {
                    events.append(TimelineEvent(
                        id: "lab-cross-in:\(key):\(current.date.timeIntervalSince1970)",
                        date: current.date,
                        title: "\(name) returned to range",
                        detail: "\(name) returned to its reference range: \(prevText) → \(currText) \(unit)",
                        category: .lab,
                        significance: .notable,
                        systemImage: "checkmark.circle.fill"
                    ))
                } else if abs(percentChange) >= 20 {
                    let changeText = String(format: "%+.0f%%", percentChange)
                    events.append(TimelineEvent(
                        id: "lab-change:\(key):\(current.date.timeIntervalSince1970)",
                        date: current.date,
                        title: "\(name) changed \(changeText)",
                        detail: "\(name) changed \(changeText): \(prevText) → \(currText) \(unit)",
                        category: .lab,
                        significance: .notable,
                        systemImage: "arrow.up.arrow.down.circle.fill"
                    ))
                }
            }
        }
        return events
    }

    // MARK: Score

    private static func scoreEvents(scores: [ScoreSnapshot]) -> [TimelineEvent] {
        let sorted = scores.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return [] }

        var events: [TimelineEvent] = []
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let delta = current.score - previous.score
            guard abs(delta) >= 5 else { continue }
            let verb = delta > 0 ? "rose" : "fell"
            events.append(TimelineEvent(
                id: "score:\(current.date.timeIntervalSince1970)",
                date: current.date,
                title: "Health score \(verb)",
                detail: "Health score \(verb) \(previous.score) → \(current.score)",
                category: .score,
                significance: .notable,
                systemImage: delta > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
            ))
        }
        return events
    }

    // MARK: Medications

    private static func medicationEvents(medications: [Medication]) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        for medication in medications {
            let dosageText = [medication.dosage, medication.frequency]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            events.append(TimelineEvent(
                id: "med-start:\(medication.name)|\(medication.startDate.timeIntervalSince1970)",
                date: medication.startDate,
                title: "Started \(medication.name)",
                detail: dosageText.isEmpty ? "Started \(medication.name)." : "Started \(medication.name) — \(dosageText).",
                category: .medication,
                significance: .routine,
                systemImage: "pills.fill"
            ))
            if let endDate = medication.endDate {
                events.append(TimelineEvent(
                    id: "med-end:\(medication.name)|\(endDate.timeIntervalSince1970)",
                    date: endDate,
                    title: "Ended \(medication.name)",
                    detail: "\(medication.name) treatment ended.",
                    category: .medication,
                    significance: .routine,
                    systemImage: "pills.circle"
                ))
            }
        }
        return events
    }

    // MARK: Vital trends
    //
    // Reuses `AnalysisEngine.trend(points:range:)` — the same regression
    // helper used for review findings and the Trends chart — rather than
    // recomputing a slope here. A crossing event only fires when the
    // window's first sample was inside the healthy range and the latest
    // sample has moved out of it, so this is strictly a subset of what
    // `.worsening` already reports.

    private static func vitalTrendEvents(vitals: [VitalSample], now: Date) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let windowStart = now.addingTimeInterval(-vitalTrendWindow)

        for type in VitalType.allCases {
            guard let range = type.healthyRange else { continue }
            let recent = vitals
                .filter { $0.type == type && $0.date >= windowStart && $0.date <= now }
                .sorted { $0.date < $1.date }
            guard recent.count >= 3,
                  let first = recent.first,
                  let last = recent.last,
                  range.contains(first.value),
                  !range.contains(last.value) else { continue }

            let points = recent.map { (date: $0.date, value: $0.value) }
            guard let (direction, percentChange) = AnalysisEngine.trend(points: points, range: range),
                  direction == .worsening else { continue }

            let changeText = String(format: "%+.0f%%", percentChange)
            events.append(TimelineEvent(
                id: "vital-trend:\(type.rawValue):\(last.date.timeIntervalSince1970)",
                date: last.date,
                title: "\(type.displayName) trending out of range",
                detail: "\(type.displayName) moved outside its healthy range over the last 30 days (\(changeText)): \(first.value.compactFormatted) → \(last.value.compactFormatted) \(type.unit)",
                category: .vital,
                significance: .notable,
                systemImage: type.systemImage
            ))
        }
        return events
    }
}
