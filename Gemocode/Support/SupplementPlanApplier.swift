import Foundation
import SwiftData

// MARK: - SupplementPlanApplier
//
// Shared, testable extraction of "turn an ActionPlan's PlanItems into
// Medication rows with a daily reminder" — originally
// `ActionPlanView.addPlanAndSetReminders`'s inline logic, now a single
// helper so `ScanReportView`'s AUTOMATIC post-save supplement add (owner
// decision: supplements are added automatically, never offered as a choice)
// and `ActionPlanView`'s explicit "Add Plan + Set Reminders" button both
// create/skip/schedule identically instead of maintaining two copies of the
// same rule.
//
// Pure with respect to *what* gets created (deterministic given the same
// `items` and existing `Medication` rows); the only side effects are the
// SwiftData insert/delete on `context` and whatever `schedule` does with the
// new `Medication` (callers own notification scheduling, exactly like
// `ActionPlanView` always has — this file never imports/calls
// `NotificationService` directly so it stays test-friendly with no
// UNUserNotificationCenter interaction).

enum SupplementPlanApplier {

    // MARK: - Display text (mirrors ActionPlanView's own private helpers)

    /// Stable, localized supplement name for a `SupplementForm` — the same
    /// display name `ActionPlanView.supplementName(_:)` shows in the "Start"
    /// list, kept here too (duplicated, not shared) so this file can use it
    /// both to build the `Medication.name` and to match against
    /// already-present medications by name.
    static func supplementName(_ form: SupplementForm) -> String {
        switch form {
        case .vitaminD3: String(localized: "Vitamin D3")
        case .ironBisglycinate: String(localized: "Iron bisglycinate")
        case .vitaminB12: String(localized: "Vitamin B12")
        case .folate: String(localized: "Folate")
        case .magnesium: String(localized: "Magnesium")
        }
    }

    static func frequencyDisplayName(_ frequency: SupplementFrequency) -> String {
        switch frequency {
        case .daily: String(localized: "daily")
        case .everyOtherDay: String(localized: "every other day")
        }
    }

    static func timingDisplayName(_ timing: SupplementTiming) -> String? {
        switch timing {
        case .none: nil
        case .withFattyMeal: String(localized: "with a fatty meal")
        case .emptyStomachWithVitaminC: String(localized: "empty stomach + vitamin C")
        }
    }

    /// "1500 IU" — the dose midpoint, not the full label range. A real
    /// medication list reads better with one practical number than a label
    /// range (the range itself stays fully visible in `ActionPlanView`'s own
    /// "Start" row, which renders straight from `PlanItem.doseLow`/`doseHigh`
    /// and never reads this stored text back).
    static func doseMidpointText(_ item: PlanItem) -> String {
        let midpoint = (item.doseLow + item.doseHigh) / 2
        return "\(midpoint.compactFormatted) \(item.doseUnit.rawValue)"
    }

    /// "daily · with a fatty meal" — frequency plus, when this supplement
    /// has one, its timing note folded into the same field (`Medication` has
    /// no separate timing column). Falls back to just the frequency when
    /// there's no timing note (`SupplementTiming.none`).
    static func frequencyAndTimingText(_ item: PlanItem) -> String {
        let frequency = frequencyDisplayName(item.frequency)
        guard let timing = timingDisplayName(item.timing) else { return frequency }
        return "\(frequency) · \(timing)"
    }

    // MARK: - Matching

    /// Whether some existing medication already covers `form` — matched by
    /// its stable display name, case-insensitively. `Medication` has no
    /// dedicated "which supplement form is this" column, so name is the only
    /// honest match key available; it's also exactly the name this same
    /// applier always writes, so a supplement it created earlier is always
    /// found again by a later `apply` call.
    static func isAlreadyPresent(_ form: SupplementForm, in medications: [Medication]) -> Bool {
        let name = supplementName(form).lowercased()
        return medications.contains { $0.name.lowercased() == name }
    }

    // MARK: - Apply / undo

    /// Creates one `Medication` per `item` in `items` — SKIPPING any whose
    /// supplement form is already present among `context`'s existing
    /// `Medication` rows (see `isAlreadyPresent`), or that's a repeat within
    /// `items` itself — schedules each new one via `schedule` (callers
    /// supply the actual `NotificationService.requestAuthorization()` +
    /// `scheduleDailyReminder` call, exactly as `ActionPlanView` always has),
    /// and returns only the newly created `Medication`s, so a caller can
    /// show/undo exactly what this call added.
    ///
    /// Every created `Medication` gets a daily reminder enabled at the same
    /// 9 AM default `MedicationsView.AddMedicationSheet` uses for a
    /// brand-new medication, and `purpose` = "Suggested by your Action
    /// Plan" — unchanged from `ActionPlanView`'s original behavior.
    @discardableResult
    static func apply(
        items: [PlanItem],
        context: ModelContext,
        schedule: (Medication) -> Void
    ) -> [Medication] {
        guard !items.isEmpty else { return [] }

        let existing = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        var knownNames = Set(existing.map { $0.name.lowercased() })

        let reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        var created: [Medication] = []

        for item in items {
            let name = supplementName(item.supplementForm)
            let key = name.lowercased()
            guard !knownNames.contains(key) else { continue }
            knownNames.insert(key)

            let medication = Medication(
                name: name,
                dosage: doseMidpointText(item),
                frequency: frequencyAndTimingText(item),
                purpose: String(localized: "Suggested by your Action Plan"),
                startDate: .now
            )
            medication.reminderEnabled = true
            medication.reminderTime = reminderTime
            context.insert(medication)
            created.append(medication)
            schedule(medication)
        }

        return created
    }

    /// Undo for `apply(...)`: cancels each medication's scheduled reminder
    /// and deletes it from `context`. Safe to call with a subset or the full
    /// list `apply` returned; deleting an already-deleted medication is a
    /// no-op on `ModelContext`.
    static func unapply(_ medications: [Medication], context: ModelContext) {
        for medication in medications {
            NotificationService.cancelReminder(id: medication.reminderID)
            context.delete(medication)
        }
    }
}
