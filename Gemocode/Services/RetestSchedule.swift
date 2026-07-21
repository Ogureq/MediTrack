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
    static var disclaimer: String {
        String(
            localized: "retest.disclaimer",
            defaultValue: "Commonly recommended intervals — your doctor may advise a different schedule for you.",
            table: "Engine"
        )
    }

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

    /// Convenience over `items(reports:now:)`: the single `.upcoming` item
    /// with the soonest `dueDate` — what a "you're caught up, next up is…"
    /// dashboard state should surface. `nil` when there's no upcoming item
    /// (no tracked tests at all, or everything is overdue/due soon).
    static func nextUpcoming(reports: [MedicalReport], now: Date, calendar: Calendar = .current) -> RetestItem? {
        items(reports: reports, now: now, calendar: calendar)
            .filter { $0.status == .upcoming }
            .min { $0.dueDate < $1.dueDate }
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

// MARK: - Draw bundling

/// A group of `RetestItem`s that make sense to draw in a single blood-draw
/// visit — "Next draw — 3 tests bundled" in the design. Purely derived data;
/// no persistence, no `Date()` inside (see `RetestSchedule.nextDraw`).
struct DrawBundle {
    /// The day this bundle should be drawn: `now` when anything in the
    /// bundle is overdue (go now), otherwise the earliest due date among the
    /// non-overdue (due-soon) items being bundled — see
    /// `RetestSchedule.nextDraw` for the full anchor rule.
    let date: Date
    /// Every item folded into this draw, sorted the same way
    /// `RetestSchedule.items` sorts (overdue, then due soon, then upcoming;
    /// ascending due date within each group).
    let items: [RetestItem]
    /// `true` if any bundled test requires fasting — the strictest
    /// requirement wins, since one fasting test means the whole visit must
    /// be fasted.
    let requiresFasting: Bool
    /// See `RetestSchedule.estimatedSavings(forBundleOf:)` for the model.
    /// `nil` for a bundle of 0 or 1 tests — there is no second visit being
    /// avoided, so there is nothing honest to advertise as "saved".
    let estimatedSavings: Int?
}

extension RetestSchedule {

    /// A test due within this many days of the bundle's anchor date (see
    /// `nextDraw`) is pulled into the same draw rather than left for its own
    /// later visit.
    static let defaultDrawWindowDays = 30

    /// Typical US self-pay (cash) price per test, in whole dollars —
    /// deliberately conservative, round figures. Covers only the interval
    /// catalog's tests (the same ids as `intervalMonthsByCatalogID`); every
    /// other catalog id (situational markers, nutrients only rechecked after
    /// an abnormal result, etc.) returns `nil` from `estimatedPrice(for:)`.
    ///
    /// These are NOT real-time market prices, a specific lab's price list, or
    /// an insurance-negotiated rate — they exist only to make "you're
    /// bundling N tests" money language feel roughly honest. Any UI
    /// surfacing them must show `pricingFootnote` alongside.
    private static let rawPrices: [(id: String, price: Int)] = [
        // Hematology (CBC) — components of one CBC draw.
        ("hemoglobin", 8),
        ("hematocrit", 8),
        ("redBloodCells", 8),
        ("whiteBloodCells", 8),
        ("platelets", 8),
        ("mcv", 8),
        ("mch", 8),
        ("mchc", 8),
        ("rdw", 8),
        ("neutrophilsPercent", 8),
        ("lymphocytesPercent", 8),

        // Lipid panel.
        ("totalCholesterol", 10),
        ("ldlCholesterol", 10),
        ("hdlCholesterol", 10),
        ("triglycerides", 10),

        // Metabolic.
        ("fastingGlucose", 12),
        ("hba1c", 15),

        // Kidney panel & electrolytes.
        ("sodium", 8),
        ("potassium", 8),
        ("chloride", 8),
        ("calcium", 10),
        ("magnesium", 15),
        ("phosphorus", 12),
        ("creatinine", 10),
        ("bun", 10),
        ("egfr", 10),
        ("uricAcid", 15),

        // Liver panel.
        ("alt", 10),
        ("ast", 10),
        ("alp", 10),
        ("ggt", 20),
        ("totalBilirubin", 10),
        ("albumin", 10),
        ("totalProtein", 10),

        // Thyroid.
        ("tsh", 20),
        ("freeT4", 25),
        ("freeT3", 30),

        // Vitamin D.
        ("vitaminD", 40),
    ]

    /// Fast lookup, keyed by lowercased catalog id.
    private static let priceByCatalogID: [String: Int] = {
        var dict = [String: Int](minimumCapacity: rawPrices.count)
        for entry in rawPrices {
            dict[entry.id.lowercased()] = entry.price
        }
        return dict
    }()

    /// Typical self-pay price for a catalog id, in whole USD — `nil` when
    /// the id isn't in the interval catalog's price table. Case-insensitive.
    static func estimatedPrice(for testID: String) -> Int? {
        priceByCatalogID[testID.lowercased()]
    }

    /// Roughly what a single lab-visit blood draw costs on its own, beyond
    /// the tests themselves — the fee this app's bundling avoids paying more
    /// than once.
    static let drawFeePerVisit = 15

    /// Stable, English-only footnote for any UI that shows `estimatedPrice`,
    /// `estimatedSavings`, or `estimatedEarlyTestingWaste` figures — views
    /// are responsible for localizing it.
    static let pricingFootnote = "Estimated typical self-pay prices — your lab and location may differ."

    /// Number of catalog tests with a suggested re-test cadence — i.e. the
    /// tests that can ever appear as a `RetestItem` (currently 38). This is
    /// NOT the "46 tests tracked" figure the design shows; that one is
    /// `LabCatalog.count`, the full reference catalog regardless of whether
    /// a test has a re-test cadence. Kept as a separate constant rather than
    /// reusing `LabCatalog.count` so the two meanings don't get confused at
    /// the call site.
    static let trackedTestCount: Int = intervalMonthsByCatalogID.count

    /// Estimated dollars saved by drawing every bundled test in one visit
    /// instead of separate visits, one per test. Model: each additional test
    /// folded into an existing visit avoids one extra `drawFeePerVisit` — this
    /// is NOT a claimed panel discount on the tests themselves (this catalog
    /// has no real insurance/cash panel pricing to draw on), just the visits
    /// you skip by bundling. A bundle of `count` tests avoids `count - 1`
    /// extra draws; `nil` for `count <= 1`, since there's no second visit
    /// being avoided.
    static func estimatedSavings(forBundleOf count: Int) -> Int? {
        guard count > 1 else { return nil }
        return drawFeePerVisit * (count - 1)
    }

    /// Money that would be wasted by testing `item` right now, before it's
    /// actually due — "NOT DUE — DON'T PAY YET". `nil` unless `item` is
    /// currently `.upcoming` (re-derived from `item.dueDate` against `now`,
    /// not from `item.status`, so a stale/reused `RetestItem` can't produce a
    /// wrong answer), and `nil` when the test has no price in
    /// `estimatedPrice(for:)`.
    static func estimatedEarlyTestingWaste(for item: RetestItem, now: Date, calendar: Calendar = .current) -> Int? {
        guard classify(dueDate: item.dueDate, now: now, calendar: calendar) == .upcoming else { return nil }
        return estimatedPrice(for: item.id)
    }

    /// Bundles every item that makes sense to draw together right now into
    /// one `DrawBundle` — "Next draw — N tests bundled" — or `nil` when
    /// `items` is empty.
    ///
    /// Always includes every `.overdue` and `.dueSoon` item (mirrors
    /// `dueOrSoon`). The **anchor date** for that bundle is:
    /// - `now`, if anything in it is `.overdue` (you'd go get this drawn
    ///   today, not on some date that's already in the past); otherwise
    /// - the earliest due date among the (non-overdue) `.dueSoon` items —
    ///   the date you'd actually schedule the visit for.
    ///
    /// This mirrors how `DashboardView.nextDrawCard` currently decides what
    /// to show: it names `dueOrSoon` items when there are any, and otherwise
    /// falls back to the single soonest `.upcoming` item — so when there is
    /// no overdue/due-soon item at all, the anchor becomes the soonest
    /// `.upcoming` item's own due date, and the bundle is seeded with just
    /// that item (the Dashboard's "next up" case).
    ///
    /// On top of that seed, any `.upcoming` item whose due date falls within
    /// `windowDays` of the anchor (never in the past relative to the anchor)
    /// is folded in too — the "you're already coming in, might as well" set.
    ///
    /// `requiresFasting` is `true` if any bundled test requires fasting.
    /// `estimatedSavings` follows `estimatedSavings(forBundleOf:)`.
    static func nextDraw(
        items: [RetestItem],
        now: Date,
        windowDays: Int = defaultDrawWindowDays,
        calendar: Calendar = .current
    ) -> DrawBundle? {
        guard !items.isEmpty else { return nil }

        let dueOrSoonItems = items.filter { $0.status != .upcoming }
        let upcomingItems = items.filter { $0.status == .upcoming }

        let anchor: Date
        let seedItems: [RetestItem]
        if !dueOrSoonItems.isEmpty {
            seedItems = dueOrSoonItems
            let hasOverdue = dueOrSoonItems.contains { $0.status == .overdue }
            if hasOverdue {
                anchor = now
            } else {
                anchor = dueOrSoonItems.map(\.dueDate).min() ?? now
            }
        } else if let soonestUpcoming = upcomingItems.min(by: { $0.dueDate < $1.dueDate }) {
            // Nothing due/soon: seed on the soonest upcoming item, mirroring
            // the Dashboard's "you're caught up, next up is…" fallback.
            anchor = soonestUpcoming.dueDate
            seedItems = [soonestUpcoming]
        } else {
            return nil
        }

        let seededIDs = Set(seedItems.map(\.id))
        let anchorDay = calendar.startOfDay(for: anchor)
        let windowedUpcoming = upcomingItems.filter { item in
            guard !seededIDs.contains(item.id) else { return false }
            let days = calendar.dateComponents(
                [.day],
                from: anchorDay,
                to: calendar.startOfDay(for: item.dueDate)
            ).day ?? Int.max
            return days >= 0 && days <= windowDays
        }

        let bundledItems = (seedItems + windowedUpcoming).sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
            return lhs.dueDate < rhs.dueDate
        }

        let requiresFasting = bundledItems.contains { LabCatalog.reference(for: $0.id)?.requiresFasting == true }

        return DrawBundle(
            date: anchor,
            items: bundledItems,
            requiresFasting: requiresFasting,
            estimatedSavings: estimatedSavings(forBundleOf: bundledItems.count)
        )
    }
}
