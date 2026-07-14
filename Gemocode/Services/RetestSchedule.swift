import Foundation

// MARK: - Retest status

/// How urgently a tracked lab test is due to be repeated, judged purely from
/// `RetestItem.dueDate` versus `now` — see `RetestSchedule.items(reports:now:)`.
enum RetestStatus: Equatable {
    case overdue
    case dueSoon
    case upcoming
}

// MARK: - Retest item

/// One catalog-tracked lab test's re-test status: when it was last measured
/// (the latest result for that series across every saved report), when it's
/// next due given `RetestSchedule`'s suggested interval, and how urgent that
/// is right now.
struct RetestItem: Identifiable, Equatable {
    /// The lab's catalog id, lowercased — the same key `LabResult.seriesKey`
    /// uses for a catalog-matched result.
    let id: String
    let displayName: String
    let lastTestedAt: Date
    let intervalMonths: Int
    let dueDate: Date
    let status: RetestStatus
}

// MARK: - Retest schedule

/// Pure, deterministic engine answering "when should I re-test this?" from
/// data already stored on-device. Mirrors `AnalysisEngine`'s and
/// `QuarterlyReview`'s style: no `Date()` inside — `now` (and `calendar`,
/// defaulted to `.current`) are always passed in, so results are fully
/// reproducible in tests.
///
/// The intervals below are **commonly recommended cadences for a generally
/// healthy adult with no condition that would call for closer monitoring** —
/// a suggestion, not a personalized or clinical schedule. Any UI surfacing
/// `RetestItem`s must display `RetestSchedule.disclaimer` alongside them.
enum RetestSchedule {

    /// Must accompany any UI list of `RetestItem`s — these are general
    /// cadences, not a prescription. Educational, not diagnostic.
    static let disclaimer = "Commonly recommended intervals — your doctor may advise a different schedule for you."

    /// A test due within this many days counts as `.dueSoon` rather than
    /// `.upcoming`.
    static let dueSoonWindowDays = 30

    /// Suggested re-test cadence, in months, per `LabCatalog` test id.
    /// Conservative, mainstream defaults for general wellness monitoring —
    /// e.g. HbA1c uses the general 6-month cadence (the 3-month cadence used
    /// for active diabetes management is a clinical decision this app
    /// doesn't make). Tests with no entry here (situational markers like
    /// CRP/ESR, or nutrient levels normally only rechecked after an abnormal
    /// result, such as B12/folate/ferritin/iron/TIBC, or fasting insulin)
    /// simply never appear as "due" — this list intentionally under-covers
    /// rather than invents an aggressive cadence.
    private static let rawIntervals: [(id: String, months: Int)] = [
        // Hematology (CBC) — annual as part of routine bloodwork.
        ("hemoglobin", 12),
        ("hematocrit", 12),
        ("redBloodCells", 12),
        ("whiteBloodCells", 12),
        ("platelets", 12),
        ("mcv", 12),
        ("mch", 12),
        ("mchc", 12),
        ("rdw", 12),
        ("neutrophilsPercent", 12),
        ("lymphocytesPercent", 12),

        // Lipid panel — annual for average risk.
        ("totalCholesterol", 12),
        ("ldlCholesterol", 12),
        ("hdlCholesterol", 12),
        ("triglycerides", 12),

        // Metabolic — HbA1c at the general 6-month cadence.
        ("fastingGlucose", 12),
        ("hba1c", 6),

        // Kidney panel & electrolytes — annual with routine bloodwork.
        ("sodium", 12),
        ("potassium", 12),
        ("chloride", 12),
        ("calcium", 12),
        ("magnesium", 12),
        ("phosphorus", 12),
        ("creatinine", 12),
        ("bun", 12),
        ("egfr", 12),
        ("uricAcid", 12),

        // Liver panel — annual.
        ("alt", 12),
        ("ast", 12),
        ("alp", 12),
        ("ggt", 12),
        ("totalBilirubin", 12),
        ("albumin", 12),
        ("totalProtein", 12),

        // Thyroid — annual.
        ("tsh", 12),
        ("freeT4", 12),
        ("freeT3", 12),

        // Vitamin D — annual; other nutrients (B12, folate, ferritin, iron,
        // TIBC) have no single mainstream default cadence and are omitted.
        ("vitaminD", 12),
    ]

    /// Fast lookup, keyed by lowercased catalog id — built once, mirroring
    /// `LabCatalog`'s own `index`.
    static let intervalMonthsByCatalogID: [String: Int] = {
        var dict = [String: Int](minimumCapacity: rawIntervals.count)
        for entry in rawIntervals {
            dict[entry.id.lowercased()] = entry.months
        }
        return dict
    }()

    /// Suggested cadence, in months, for a catalog id — nil when the id has
    /// no sensible general default (see `rawIntervals`). Case-insensitive,
    /// like `LabCatalog.reference(for:)`.
    static func intervalMonths(for catalogID: String) -> Int? {
        intervalMonthsByCatalogID[catalogID.lowercased()]
    }

    // MARK: Build

    /// One `RetestItem` per catalog-tracked lab series that appears anywhere
    /// across `reports`, using the LATEST result date for that series across
    /// every report (not just the most recent report). Labs entered without
    /// a catalog id, or with a catalog id absent from
    /// `intervalMonthsByCatalogID`, never produce an item.
    ///
    /// Sorted overdue first, then due soon, then upcoming; within each group,
    /// ascending by due date (so the oldest/most-overdue item leads).
    static func items(reports: [MedicalReport], now: Date, calendar: Calendar = .current) -> [RetestItem] {
        var latestDateByID: [String: Date] = [:]
        var nameByID: [String: String] = [:]

        for report in reports {
            for result in report.labResults {
                guard let catalogID = result.catalogID?.lowercased(),
                      intervalMonthsByCatalogID[catalogID] != nil else { continue }
                if let existing = latestDateByID[catalogID], existing >= result.date {
                    continue
                }
                latestDateByID[catalogID] = result.date
                nameByID[catalogID] = LabCatalog.reference(for: catalogID)?.name ?? result.displayName
            }
        }

        let items: [RetestItem] = latestDateByID.compactMap { catalogID, lastDate in
            guard let months = intervalMonthsByCatalogID[catalogID] else { return nil }
            let dueDate = calendar.date(byAdding: .month, value: months, to: lastDate) ?? lastDate
            let status = classify(dueDate: dueDate, now: now, calendar: calendar)
            return RetestItem(
                id: catalogID,
                displayName: nameByID[catalogID] ?? catalogID,
                lastTestedAt: lastDate,
                intervalMonths: months,
                dueDate: dueDate,
                status: status
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
            return lhs.dueDate < rhs.dueDate
        }
    }

    /// Convenience over `items(reports:now:)`: only the tests that need
    /// attention now (`.overdue` or `.dueSoon`) — what a "Tests Due" UI
    /// surface should show.
    static func dueOrSoon(reports: [MedicalReport], now: Date, calendar: Calendar = .current) -> [RetestItem] {
        items(reports: reports, now: now, calendar: calendar).filter { $0.status != .upcoming }
    }

    // MARK: - Private helpers

    /// Classifies a due date against `now` using whole calendar days (via
    /// `startOfDay`), so a time-of-day mismatch between a stored result date
    /// and `now` never tips a boundary the wrong way.
    private static func classify(dueDate: Date, now: Date, calendar: Calendar) -> RetestStatus {
        let daysUntilDue = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
        if daysUntilDue < 0 { return .overdue }
        if daysUntilDue <= dueSoonWindowDays { return .dueSoon }
        return .upcoming
    }

    private static func statusRank(_ status: RetestStatus) -> Int {
        switch status {
        case .overdue: 0
        case .dueSoon: 1
        case .upcoming: 2
        }
    }
}
