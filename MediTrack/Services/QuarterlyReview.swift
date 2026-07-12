import Foundation

// MARK: - Quarterly review building blocks

/// Which way a metric moved, judged only where the clinical meaning of
/// "lower" vs "higher" is unambiguous. Everything else (weight, and any
/// metric without a clear improve/worsen semantic) reports `.steady` and is
/// presented neutrally as "changed" rather than good or bad news.
enum Direction: Equatable {
    case improved
    case worsened
    case steady
}

/// The change in one vital type across the review window. For blood
/// pressure this tracks the systolic (`value`) component only — `VitalSample`
/// stores diastolic separately and this summary intentionally keeps one
/// number per metric.
struct VitalChange: Equatable {
    let type: VitalType
    let firstValue: Double
    let lastValue: Double
    let direction: Direction
}

/// The change in one lab test (matched by catalog id) between its most
/// recent in-window result and the closest earlier result before that,
/// which may itself be from before the window (the pre-quarter baseline).
struct LabChange: Equatable {
    let name: String
    let previousValue: Double
    let latestValue: Double
    let unit: String
    let direction: Direction
}

/// A deterministic, on-device recap of the last ~90 days, built entirely
/// from records already stored locally. No AI, no network — see
/// `QuarterlyReview.build(...)`.
struct QuarterlyReviewSummary: Equatable {
    let periodStart: Date
    let periodEnd: Date
    let startScore: Int?
    let endScore: Int?
    let scoreDelta: Int?
    let vitalChanges: [VitalChange]
    let labChanges: [LabChange]
    let goalsAchieved: [String]
    let longestStreak: Int
    let symptomCount: Int
    let doctorQuestions: [String]

    static let disclaimer = "A look back at your own data — educational, not medical advice."

    /// Plain-text recap for the sheet's `ShareLink`. Mirrors only what's
    /// already visible on screen — no additional raw values are pulled in.
    var shareText: String {
        var lines: [String] = []
        lines.append("MediTrack Quarterly Review")
        lines.append("\(periodStart.formatted(date: .abbreviated, time: .omitted)) – \(periodEnd.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")

        if let startScore, let endScore {
            var scoreLine = "Health score: \(startScore) → \(endScore)"
            if let scoreDelta {
                scoreLine += " (\(scoreDelta >= 0 ? "+" : "")\(scoreDelta))"
            }
            lines.append(scoreLine)
            lines.append("")
        }

        if !vitalChanges.isEmpty || !labChanges.isEmpty {
            lines.append("WHAT CHANGED")
            for change in vitalChanges {
                lines.append("• \(change.type.displayName): \(change.firstValue.compactFormatted) → \(change.lastValue.compactFormatted) (\(change.direction.label))")
            }
            for change in labChanges {
                lines.append("• \(change.name): \(change.previousValue.compactFormatted) → \(change.latestValue.compactFormatted) \(change.unit) (\(change.direction.label))")
            }
            lines.append("")
        }

        lines.append("WINS")
        if longestStreak >= 2 {
            lines.append("• Longest reminder streak: \(longestStreak) days")
        }
        for goal in goalsAchieved {
            lines.append("• Goal achieved: \(goal)")
        }
        if symptomCount == 0 {
            lines.append("• No symptoms logged this quarter")
        }
        lines.append("")

        if !doctorQuestions.isEmpty {
            lines.append("QUESTIONS FOR YOUR DOCTOR")
            for question in doctorQuestions {
                lines.append("• \(question)")
            }
            lines.append("")
        }

        lines.append(Self.disclaimer)
        return lines.joined(separator: "\n")
    }
}

extension Direction {
    /// Neutral label used in both the UI and the shared plain-text recap.
    var label: String {
        switch self {
        case .improved: "Improved"
        case .worsened: "Worsened"
        case .steady: "Changed"
        }
    }
}

// MARK: - Quarterly review

/// Pure, deterministic generator for the Quarterly Health Review ritual.
/// Mirrors `AnalysisEngine`'s style: no `Date()` inside, `now` and
/// `calendar` are always passed in, and nothing here calls out to AI or the
/// network — the whole recap is built from records already on-device.
enum QuarterlyReview {

    /// UserDefaults key holding the last completion time as a
    /// `timeIntervalSince1970` double.
    static let lastCompletedKey = "quarterly.lastCompletedAt"

    /// Minimum span of data, in days, before the ritual is offered at all.
    private static let minimumDataDays = 14
    /// How often the ritual repeats once completed.
    private static let cadenceDays = 90
    /// Length of the recap window itself.
    private static let windowDays = 90

    /// Lab catalog ids this review can judge a direction for, and whether a
    /// *lower* value is the improvement (`true`) or a *higher* value is
    /// (`false`). Any catalog id not listed here — or any manually-entered
    /// test with no catalog id — renders as a neutral "changed".
    private static let labLowerIsBetter: [String: Bool] = [
        "ldlcholesterol": true,
        "triglycerides": true,
        "fastingglucose": true,
        "hdlcholesterol": false,
    ]

    /// A resting heart rate outside this band is too far from typical rest
    /// to responsibly call "better" or "worse" from the number alone.
    private static let plausibleRestingHeartRate: ClosedRange<Double> = 40...120

    // MARK: Due-ness

    /// Whether the recap should be offered: there must be at least
    /// `minimumDataDays` of history, and either the ritual has never been
    /// completed or it's been at least `cadenceDays` since it last was.
    static func isDue(lastCompleted: Date?, earliestData: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let earliestData else { return false }
        let daysOfData = calendar.dateComponents([.day], from: earliestData, to: now).day ?? 0
        guard daysOfData >= minimumDataDays else { return false }

        guard let lastCompleted else { return true }
        let daysSinceCompleted = calendar.dateComponents([.day], from: lastCompleted, to: now).day ?? 0
        return daysSinceCompleted >= cadenceDays
    }

    // MARK: Build

    static func build(
        snapshots: [ScoreSnapshot],
        vitals: [VitalSample],
        labResults: [LabResult],
        goals: [HealthGoal],
        reminders: [Reminder],
        symptoms: [SymptomEntry],
        now: Date,
        calendar: Calendar
    ) -> QuarterlyReviewSummary {
        let periodEnd = now
        let periodStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now.addingTimeInterval(-Double(windowDays) * 86_400)

        func inWindow(_ date: Date) -> Bool {
            date >= periodStart && date <= periodEnd
        }

        // --- Score trajectory ---
        let windowSnapshots = snapshots.filter { inWindow($0.date) }.sorted { $0.date < $1.date }
        let startScore = windowSnapshots.first?.score
        let endScore = windowSnapshots.last?.score
        let scoreDelta: Int?
        if windowSnapshots.count >= 2, let first = windowSnapshots.first, let last = windowSnapshots.last {
            scoreDelta = last.score - first.score
        } else {
            scoreDelta = nil
        }

        // --- Vitals ---
        let vitalChanges = buildVitalChanges(vitals: vitals, inWindow: inWindow)

        // --- Labs ---
        let labChanges = buildLabChanges(labResults: labResults, inWindow: inWindow)

        // --- Goals achieved during the window ---
        let goalsAchieved = buildGoalsAchieved(goals: goals, vitals: vitals, periodStart: periodStart, inWindow: inWindow)

        // --- Longest reminder-completion streak in the window ---
        let longestStreak = reminders
            .map { reminder -> Int in
                let completionDates = (reminder.completions ?? [])
                    .map(\.date)
                    .filter(inWindow)
                return longestConsecutiveDayStreak(dates: completionDates, calendar: calendar)
            }
            .max() ?? 0

        // --- Symptoms logged in the window ---
        let symptomCount = symptoms.filter { inWindow($0.date) }.count

        // --- Doctor questions, from worsened items only ---
        var doctorQuestions: [String] = []
        for change in vitalChanges where change.direction == .worsened {
            doctorQuestions.append(doctorQuestion(label: change.type.displayName.lowercased(), previous: change.firstValue, latest: change.lastValue))
        }
        for change in labChanges where change.direction == .worsened {
            doctorQuestions.append(doctorQuestion(label: change.name, previous: change.previousValue, latest: change.latestValue))
        }

        return QuarterlyReviewSummary(
            periodStart: periodStart,
            periodEnd: periodEnd,
            startScore: startScore,
            endScore: endScore,
            scoreDelta: scoreDelta,
            vitalChanges: vitalChanges,
            labChanges: labChanges,
            goalsAchieved: goalsAchieved,
            longestStreak: longestStreak,
            symptomCount: symptomCount,
            doctorQuestions: doctorQuestions
        )
    }

    // MARK: Completion bookkeeping

    static func markCompleted(now: Date, defaults: UserDefaults) {
        defaults.set(now.timeIntervalSince1970, forKey: lastCompletedKey)
    }

    static func lastCompleted(defaults: UserDefaults) -> Date? {
        let stored = defaults.double(forKey: lastCompletedKey)
        guard stored > 0 else { return nil }
        return Date(timeIntervalSince1970: stored)
    }

    // MARK: - Private helpers

    /// One entry per `VitalType` that has at least two samples inside the
    /// window, comparing the earliest to the latest in-window reading.
    private static func buildVitalChanges(vitals: [VitalSample], inWindow: (Date) -> Bool) -> [VitalChange] {
        var changes: [VitalChange] = []
        for type in VitalType.allCases {
            let samples = vitals.filter { $0.type == type && inWindow($0.date) }.sorted { $0.date < $1.date }
            guard samples.count >= 2, let first = samples.first, let last = samples.last else { continue }
            let direction = vitalDirection(type, first: first.value, last: last.value)
            changes.append(VitalChange(type: type, firstValue: first.value, lastValue: last.value, direction: direction))
        }
        return changes
    }

    /// One entry per catalog-matched lab test that has an in-window result
    /// and an earlier result (in or before the window) to compare against.
    /// Manually-entered tests without a catalog id are skipped — there's no
    /// stable key to track them across reports.
    private static func buildLabChanges(labResults: [LabResult], inWindow: (Date) -> Bool) -> [LabChange] {
        let catalogResults: [(catalogID: String, result: LabResult)] = labResults.compactMap { result in
            guard let catalogID = result.catalogID?.lowercased() else { return nil }
            return (catalogID, result)
        }
        let grouped = Dictionary(grouping: catalogResults) { $0.catalogID }

        var changes: [LabChange] = []
        for (catalogID, entries) in grouped {
            let sorted = entries.map { $0.result }.sorted { $0.date < $1.date }
            guard let latest = sorted.last(where: { inWindow($0.date) }) else { continue }
            guard let baseline = sorted.last(where: { $0.date < latest.date }) else { continue }
            let direction = labDirection(catalogID: catalogID, previous: baseline.value, latest: latest.value)
            changes.append(LabChange(
                name: latest.displayName,
                previousValue: baseline.value,
                latestValue: latest.value,
                unit: latest.unit,
                direction: direction
            ))
        }
        return changes.sorted { $0.name < $1.name }
    }

    /// A goal counts as "achieved in this window" only when it transitions
    /// from not-achieved to achieved during the window itself — judged from
    /// the vital reading just before the window (or the goal's recorded
    /// start value) versus the latest reading inside it. This needs no
    /// completion timestamp on `HealthGoal`, which the model doesn't store.
    private static func buildGoalsAchieved(
        goals: [HealthGoal],
        vitals: [VitalSample],
        periodStart: Date,
        inWindow: (Date) -> Bool
    ) -> [String] {
        var achieved: [String] = []
        for goal in goals {
            let samples = vitals.filter { $0.type == goal.type }.sorted { $0.date < $1.date }
            let beforeWindowValue = samples.last(where: { $0.date < periodStart })?.value ?? goal.startValue
            guard let latestInWindow = samples.last(where: inWindow) else { continue }

            let wasAchieved = goal.isAchieved(latest: beforeWindowValue)
            let isAchievedNow = goal.isAchieved(latest: latestInWindow.value)
            guard isAchievedNow, !wasAchieved else { continue }

            achieved.append(goal.note.isEmpty ? "\(goal.type.displayName) goal" : goal.note)
        }
        return achieved
    }

    /// Longest run of consecutive calendar days present in `dates`, using
    /// `Calendar` day math throughout (never string/wall-clock comparisons)
    /// so it stays correct across time zones and DST — same discipline as
    /// `ReminderStreak` in RemindersView.swift, but scoped to a fixed
    /// window rather than counting backward from "today".
    private static func longestConsecutiveDayStreak(dates: [Date], calendar: Calendar) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        var longest = 0
        for day in days {
            // Only start counting from the first day of each run so every
            // run is measured exactly once.
            if let previousDay = calendar.date(byAdding: .day, value: -1, to: day), days.contains(previousDay) {
                continue
            }
            var length = 1
            var cursor = day
            while let next = calendar.date(byAdding: .day, value: 1, to: cursor), days.contains(next) {
                length += 1
                cursor = next
            }
            longest = max(longest, length)
        }
        return longest
    }

    /// Direction semantics for vitals: lower is the improvement for blood
    /// pressure (systolic) and blood glucose; resting heart rate has only a
    /// mild lower-is-better preference and only within a plausible resting
    /// band; every other vital (weight included) has no unambiguous
    /// "better" direction and always reports `.steady`.
    private static func vitalDirection(_ type: VitalType, first: Double, last: Double) -> Direction {
        switch type {
        case .bloodPressure, .bloodGlucose:
            return trendDirection(previous: first, latest: last, lowerIsBetter: true)
        case .heartRate:
            guard plausibleRestingHeartRate.contains(first), plausibleRestingHeartRate.contains(last) else { return .steady }
            return trendDirection(previous: first, latest: last, lowerIsBetter: true)
        case .weight, .oxygenSaturation, .temperature, .respiratoryRate, .sleepHours:
            return .steady
        }
    }

    /// Direction semantics for labs, from the `labLowerIsBetter` table.
    /// Anything absent from that table — including custom, non-catalog
    /// tests — reports `.steady`.
    private static func labDirection(catalogID: String, previous: Double, latest: Double) -> Direction {
        guard let lowerIsBetter = labLowerIsBetter[catalogID] else { return .steady }
        return trendDirection(previous: previous, latest: latest, lowerIsBetter: lowerIsBetter)
    }

    private static func trendDirection(previous: Double, latest: Double, lowerIsBetter: Bool) -> Direction {
        guard abs(latest - previous) > 1e-9 else { return .steady }
        let wentDown = latest < previous
        if lowerIsBetter {
            return wentDown ? .improved : .worsened
        }
        return wentDown ? .worsened : .improved
    }

    /// A neutral, non-diagnostic prompt for the "questions for your doctor"
    /// list — always phrased as a question to bring to a professional, and
    /// always derived from the direction the raw numbers actually moved.
    private static func doctorQuestion(label: String, previous: Double, latest: Double) -> String {
        let movement = latest > previous ? "rising" : "declining"
        return "Ask about your \(movement) \(label)."
    }
}
