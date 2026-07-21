import Foundation

// MARK: - Action Plan
//
// The data layer behind the "Action plan" screen (premium): for out-of-range
// lab values, a small set of rule-based, EDUCATIONAL over-the-counter
// supplement suggestions with typical label dose ranges, a medication
// interaction check, and a "keep watching" list for everything else that's
// out of range.
//
// Mirrors `AnalysisEngine`'s and `RetestSchedule`'s style: pure and
// deterministic, `now` passed in, no `Date()` inside. All display-facing
// content is structured data (ids, enums, numbers) — the only free-text
// English the engine returns is the static `disclaimer`, and the `drugA` /
// `drugB` / `explanation` / `recommendation` text on any surfaced
// `DrugInteraction`, which is inherited as-is from `MedicationInteractions`
// (already a `String(localized:)` value there, same as every other finding
// in `AnalysisEngine`).
//
// SAFETY INVARIANTS (binding):
//  - Plan items exist ONLY for the whitelisted, supplement-addressable
//    nutrient markers below. No other lab test ever produces a `PlanItem`.
//  - Never a dose or timing suggestion for a prescription drug — `PlanItem`
//    only ever wraps an OTC supplement keyed off a LOW lab value.
//  - Never anything but "keep watching" for a HIGH value, even for a
//    whitelisted nutrient (e.g. high vitamin D is keep-watching only).
//  - Every plan carries `ActionPlan.disclaimer`.

// MARK: - Supplement form

/// Stable identifiers for the small set of OTC supplements this engine can
/// suggest. These are keys, not display text — views own localization and
/// presentation (name, icon, copy).
enum SupplementForm: String, CaseIterable, Identifiable, Hashable {
    case vitaminD3
    case ironBisglycinate
    case vitaminB12
    case folate
    case magnesium

    var id: String { rawValue }

    /// A stable, non-localized name used only to feed `MedicationInteractions`
    /// (which matches against English drug/supplement name substrings). This
    /// is never returned to a view for display.
    fileprivate var interactionCheckName: String {
        switch self {
        case .vitaminD3: "Vitamin D3"
        case .ironBisglycinate: "Iron"
        case .vitaminB12: "Vitamin B12"
        case .folate: "Folate"
        case .magnesium: "Magnesium"
        }
    }
}

/// Dose unit as a stable code, not a sentence — matches how `LabReference.unit`
/// and `VitalType.unit` already store plain unit strings ("mg/dL", "kg") that
/// are not translated.
enum SupplementDoseUnit: String {
    case iu = "IU"
    case mg
    case mcg
}

enum SupplementFrequency {
    case daily
    case everyOtherDay
}

enum SupplementTiming {
    case none
    /// e.g. vitamin D3 — a fat-soluble vitamin absorbed better with dietary fat.
    case withFattyMeal
    /// e.g. iron — better absorbed away from food, and vitamin C aids uptake.
    case emptyStomachWithVitaminC
}

// MARK: - Plan items

/// A supplement suggestion for one LOW (or below-optimal) whitelisted
/// nutrient marker, with a structured dose range and a suggested retest date.
struct PlanItem: Identifiable, Hashable {
    let id = UUID()
    /// `LabCatalog` id, lowercased — matches `LabSnapshot.id`.
    let labTestID: String
    let currentValue: Double
    let unit: String
    /// The reference range this value fell short of (already sex-resolved,
    /// since it comes straight from `HealthReview.labSnapshots`).
    let range: ClosedRange<Double>?
    /// Always `.low` or `.criticalLow` — see safety invariants above.
    let status: LabStatus
    let supplementForm: SupplementForm
    let doseLow: Double
    let doseHigh: Double
    let doseUnit: SupplementDoseUnit
    let frequency: SupplementFrequency
    let timing: SupplementTiming
    /// Anchored at the `now` passed to `ActionPlan.generate`.
    let suggestedRetestDate: Date

    static func == (lhs: PlanItem, rhs: PlanItem) -> Bool {
        lhs.labTestID == rhs.labTestID
            && lhs.currentValue == rhs.currentValue
            && lhs.supplementForm == rhs.supplementForm
            && lhs.suggestedRetestDate == rhs.suggestedRetestDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(labTestID)
        hasher.combine(supplementForm)
    }
}

/// An out-of-range marker with no supplement rule (or a HIGH whitelisted
/// nutrient) — nothing to suggest beyond tracking it and rechecking later.
struct KeepWatchingItem: Identifiable, Hashable {
    let id = UUID()
    let labTestID: String
    let currentValue: Double
    let unit: String
    let range: ClosedRange<Double>?
    let status: LabStatus
    let suggestedRetestDate: Date

    static func == (lhs: KeepWatchingItem, rhs: KeepWatchingItem) -> Bool {
        lhs.labTestID == rhs.labTestID
            && lhs.currentValue == rhs.currentValue
            && lhs.suggestedRetestDate == rhs.suggestedRetestDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(labTestID)
    }
}

// MARK: - Interaction check

/// Result of running proposed supplements + current medications through
/// `MedicationInteractions`. `wasChecked` distinguishes "checked, none found"
/// (there was something to check, and no hits came back) from "not checked"
/// (there was nothing to check at all — no proposed supplements and no
/// active medications).
struct ActionPlanInteractionCheck {
    let wasChecked: Bool
    let warnings: [DrugInteraction]

    static var notChecked: ActionPlanInteractionCheck {
        ActionPlanInteractionCheck(wasChecked: false, warnings: [])
    }
}

// MARK: - Action plan

struct ActionPlan {
    let generatedAt: Date
    let items: [PlanItem]
    let keepWatching: [KeepWatchingItem]
    let interactionCheck: ActionPlanInteractionCheck

    /// Must accompany any UI surfacing of `PlanItem`s or `KeepWatchingItem`s —
    /// mirrors `MedicationInteractions.disclaimer` / `HealthReview.disclaimer`.
    static var disclaimer: String {
        String(
            localized: "actionPlan.disclaimer",
            defaultValue: "Educational, not medical advice — confirm any supplement and dose with your doctor or pharmacist.",
            table: "Engine"
        )
    }

    // MARK: Rule table

    private struct SupplementRule {
        let form: SupplementForm
        /// Catalog ids this rule can trigger from, in priority order — the
        /// first one present with a LOW/critical-LOW snapshot wins, and both
        /// ids are considered "handled" so the sibling marker doesn't also
        /// spawn a duplicate keep-watching entry for the same nutrient story.
        let catalogIDs: [String]
        let doseLow: Double
        let doseHigh: Double
        let doseUnit: SupplementDoseUnit
        let frequency: SupplementFrequency
        let timing: SupplementTiming
    }

    /// Supplement-addressable nutrient markers only. Every other out-of-range
    /// lab test — including a HIGH reading on one of these five — falls
    /// through to `keepWatching` instead.
    private static let supplementRules: [SupplementRule] = [
        SupplementRule(
            form: .vitaminD3,
            catalogIDs: ["vitamind"],
            doseLow: 1000, doseHigh: 2000, doseUnit: .iu,
            frequency: .daily, timing: .withFattyMeal
        ),
        SupplementRule(
            form: .ironBisglycinate,
            catalogIDs: ["ferritin", "iron"],
            doseLow: 18, doseHigh: 27, doseUnit: .mg,
            frequency: .everyOtherDay, timing: .emptyStomachWithVitaminC
        ),
        SupplementRule(
            form: .vitaminB12,
            catalogIDs: ["vitaminb12"],
            doseLow: 500, doseHigh: 1000, doseUnit: .mcg,
            frequency: .daily, timing: .none
        ),
        SupplementRule(
            form: .folate,
            catalogIDs: ["folate"],
            doseLow: 400, doseHigh: 800, doseUnit: .mcg,
            frequency: .daily, timing: .none
        ),
        SupplementRule(
            form: .magnesium,
            catalogIDs: ["magnesium"],
            doseLow: 200, doseHigh: 400, doseUnit: .mg,
            frequency: .daily, timing: .none
        )
    ]

    /// `RetestSchedule` deliberately has no cadence for nutrient levels that
    /// are "normally only rechecked after an abnormal result" (ferritin,
    /// iron, B12, folate — see `RetestSchedule.rawIntervals`'s doc comment),
    /// so `RetestSchedule.intervalMonths(for:)` returns `nil` for them. This
    /// plan needs a retest anchor regardless, so it falls back to a
    /// conservative 3-month recheck — a commonly used follow-up window after
    /// starting supplementation for a deficiency. Vitamin D and magnesium
    /// already have a real `RetestSchedule` cadence (12 months) and use that
    /// instead.
    private static let fallbackRetestMonths = 3

    private static func retestDate(for labTestID: String, now: Date, calendar: Calendar) -> Date {
        let months = RetestSchedule.intervalMonths(for: labTestID) ?? fallbackRetestMonths
        return calendar.date(byAdding: .month, value: months, to: now) ?? now
    }

    // MARK: Generation

    /// Pure and deterministic: same `review`/`medications`/`now` always
    /// produce an identical plan. No `Date()` inside — `now` (and `calendar`,
    /// defaulted like `RetestSchedule`) are always passed in.
    static func generate(
        review: HealthReview,
        medications: [Medication],
        now: Date,
        calendar: Calendar = .current
    ) -> ActionPlan {
        var items: [PlanItem] = []
        var handledIDs: Set<String> = []

        for rule in supplementRules {
            let candidateSnapshots = rule.catalogIDs.compactMap { catalogID in
                review.labSnapshots.first { $0.id == catalogID.lowercased() }
            }
            guard let snapshot = candidateSnapshots.first(where: { $0.status == .low || $0.status == .criticalLow }) else {
                continue
            }
            handledIDs.insert(snapshot.id)

            items.append(PlanItem(
                labTestID: snapshot.id,
                currentValue: snapshot.value,
                unit: snapshot.unit,
                range: snapshot.range,
                status: snapshot.status,
                supplementForm: rule.form,
                doseLow: rule.doseLow,
                doseHigh: rule.doseHigh,
                doseUnit: rule.doseUnit,
                frequency: rule.frequency,
                timing: rule.timing,
                suggestedRetestDate: retestDate(for: snapshot.id, now: now, calendar: calendar)
            ))
        }

        // Keep watching: every other out-of-range marker (no supplement
        // rule), plus a HIGH reading on a whitelisted nutrient, plus the
        // sibling of an already-handled iron/ferritin pair if that sibling
        // is itself out of range. `labSnapshots` is already deterministically
        // ordered by `AnalysisEngine`, so a plain filter keeps that order.
        let keepWatching: [KeepWatchingItem] = review.labSnapshots
            .filter { $0.status.isOutOfRange && !handledIDs.contains($0.id) }
            .map { snapshot in
                KeepWatchingItem(
                    labTestID: snapshot.id,
                    currentValue: snapshot.value,
                    unit: snapshot.unit,
                    range: snapshot.range,
                    status: snapshot.status,
                    suggestedRetestDate: retestDate(for: snapshot.id, now: now, calendar: calendar)
                )
            }

        // Interaction check: proposed supplements + active medication names,
        // through the same educational, non-exhaustive checker AnalysisEngine
        // uses for medication-medication interactions.
        let activeMedicationNames = medications.filter(\.isActive).map(\.name)
        let supplementNames = items.map(\.supplementForm.interactionCheckName)
        let namesToCheck = supplementNames + activeMedicationNames

        let interactionCheck: ActionPlanInteractionCheck
        if namesToCheck.isEmpty {
            interactionCheck = .notChecked
        } else {
            interactionCheck = ActionPlanInteractionCheck(
                wasChecked: true,
                warnings: MedicationInteractions.check(medicationNames: namesToCheck)
            )
        }

        return ActionPlan(
            generatedAt: now,
            items: items,
            keepWatching: keepWatching,
            interactionCheck: interactionCheck
        )
    }
}
