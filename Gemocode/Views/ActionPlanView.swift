import SwiftUI
import SwiftData

/// "Action plan" (Premium): turns `HealthReview.labSnapshots` into a small,
/// rule-based set of OTC supplement suggestions via `ActionPlan.generate`
/// (supplement, dose range, timing, suggested retest date), a medication
/// interaction check against the user's current medications, and a "keep
/// watching" list for everything else out of range that has no supplement
/// rule. Presented as a sheet from `ReviewScreen`'s general Action Plan row,
/// and from `ScanReportView`'s post-save AI stage right after a scan saves
/// an out-of-range value (`scanDate` set in that case, so the header can
/// read "from <date> scan").
///
/// Gated end-to-end by `premiumStore.isPremium`, mirroring
/// `ScanReportView.lockedCard`'s presentation-only lock pattern: the whole
/// screen swaps to a lock card with a "Premium" micro-label and an unlock
/// CTA instead of any plan content.
struct ActionPlanView: View {
    let review: HealthReview
    /// Set only when opened right after a scan; `nil` from `ReviewScreen`'s
    /// general entry point, where there's no single scan this plan is "from".
    var scanDate: Date?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var premiumStore = PremiumStore.shared

    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]

    @State private var showingPaywall = false
    @State private var showingAIChat = false
    @State private var isAddingPlan = false
    @State private var confirmationMessage = ""
    @State private var showingConfirmation = false

    init(review: HealthReview, scanDate: Date? = nil) {
        self.review = review
        self.scanDate = scanDate
    }

    private var plan: ActionPlan {
        ActionPlan.generate(review: review, medications: medications, now: .now)
    }

    var body: some View {
        NavigationStack {
            Group {
                if premiumStore.isPremium {
                    unlockedBody
                } else {
                    lockedBody
                }
            }
            .ambientScreen()
            .navigationTitle("Action Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingAIChat) {
                AIChatView(review: review, profileSummary: aiProfileSummary ?? "")
            }
            .alert("Plan Added", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    // MARK: - Unlocked

    @ViewBuilder
    private var unlockedBody: some View {
        let currentPlan = plan
        if currentPlan.items.isEmpty && currentPlan.keepWatching.isEmpty {
            ContentUnavailableView(
                "Nothing to Flag Right Now",
                systemImage: "checkmark.seal",
                description: Text("Every tracked value is currently in range — there's nothing for an Action Plan to suggest.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !currentPlan.items.isEmpty {
                        startSection(currentPlan.items)
                    }
                    if currentPlan.interactionCheck.wasChecked {
                        interactionRow(currentPlan.interactionCheck)
                    }
                    if !currentPlan.keepWatching.isEmpty {
                        keepWatchingSection(currentPlan.keepWatching)
                    }
                    ctaButtons(currentPlan)
                    Text(ActionPlan.disclaimer)
                        .font(.system(size: 13))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Action Plan")
                .font(.system(size: 30, weight: .regular))
                .tracking(-0.6)
                .foregroundStyle(Editorial.ink(colorScheme))
            Spacer()
            if let scanDate {
                Text("from \(scanDate.formatted(date: .abbreviated, time: .omitted)) scan")
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
        }
    }

    // MARK: Start section

    private func startSection(_ items: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel("Start — Worth Discussing With Your Doctor")
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    planItemRow(item)
                }
            }
        }
    }

    private func planItemRow(_ item: PlanItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: planItemTitle(item))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer(minLength: 8)
                EditorialTag(verbatim: item.status.label, kind: .bad)
            }
            if let range = item.range {
                let axis = rangeBarAxis(range: range, value: item.currentValue)
                RangeBar(
                    lower: range.lowerBound,
                    upper: range.upperBound,
                    min: axis.min,
                    max: axis.max,
                    value: item.currentValue,
                    accessibilityLabel: Text("\(supplementName(item.supplementForm)) \(item.currentValue.compactFormatted) \(item.unit), \(item.status.label)")
                )
            }
            Text(verbatim: planItemCaption(item))
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(planItemTitle(item)), \(item.status.label). \(planItemCaption(item))")
    }

    /// "Vitamin D3 — 1000–2000 IU daily" — the real dose RANGE from
    /// `PlanItem.doseLow`/`doseHigh`, not a single illustrative number.
    private func planItemTitle(_ item: PlanItem) -> String {
        "\(supplementName(item.supplementForm)) — \(item.doseLow.compactFormatted)–\(item.doseHigh.compactFormatted) \(item.doseUnit.rawValue) \(frequencyDisplayName(item.frequency))"
    }

    /// "21 ng/mL → target 30+ ng/mL · with a fatty meal · retest Dec 5".
    private func planItemCaption(_ item: PlanItem) -> String {
        let currentText = "\(item.currentValue.compactFormatted) \(item.unit)"
        let targetText: String
        if let range = item.range {
            targetText = "\(range.lowerBound.compactFormatted)+ \(item.unit)"
        } else {
            targetText = String(localized: "the typical range")
        }
        var parts = [String(localized: "\(currentText) → target \(targetText)")]
        if let timing = timingDisplayName(item.timing) {
            parts.append(timing)
        }
        parts.append(String(localized: "retest \(item.suggestedRetestDate.formatted(date: .abbreviated, time: .omitted))"))
        return parts.joined(separator: " · ")
    }

    // MARK: Interaction check

    @ViewBuilder
    private func interactionRow(_ check: ActionPlanInteractionCheck) -> some View {
        if check.warnings.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .accessibilityHidden(true)
                Text(verbatim: noInteractionsText)
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel("Interactions to Review")
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    ForEach(check.warnings) { warning in
                        interactionWarningRow(warning)
                    }
                }
                Text(MedicationInteractions.disclaimer)
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .padding(.top, 8)
            }
        }
    }

    private func interactionWarningRow(_ warning: DrugInteraction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(warning.drugA) + \(warning.drugB)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer(minLength: 8)
                EditorialTag(verbatim: warning.severity.displayName, kind: interactionTagKind(warning.severity))
            }
            Text(warning.explanation)
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
            Text(warning.recommendation)
                .font(.system(size: 13))
                .foregroundStyle(Editorial.ink(colorScheme))
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    private func interactionTagKind(_ severity: InteractionSeverity) -> TagKind {
        switch severity {
        case .minor: .good
        case .moderate: .warn
        case .major: .bad
        }
    }

    private var activeMedicationNames: [String] {
        medications.filter(\.isActive).map(\.name)
    }

    private var noInteractionsText: String {
        String(localized: "No interactions found with \(joinedNames(activeMedicationNames)).")
    }

    /// English-only joiner ("A", "A or B", "A, B, or C") — kept out of the
    /// per-name loop above so the whole sentence stays one localizable key
    /// per name-count rather than composing translated fragments by hand.
    private func joinedNames(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return String(localized: "your current medications")
        case 1:
            return names[0]
        case 2:
            return String(localized: "\(names[0]) or \(names[1])")
        default:
            let allButLast = names.dropLast().joined(separator: ", ")
            return String(localized: "\(allButLast), or \(names[names.count - 1])")
        }
    }

    // MARK: Keep watching

    private func keepWatchingSection(_ items: [KeepWatchingItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel("Keep Watching")
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    keepWatchingRow(item)
                }
            }
        }
    }

    private func keepWatchingRow(_ item: KeepWatchingItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: labDisplayName(item.labTestID))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer(minLength: 8)
                EditorialTag(verbatim: item.status.label, kind: keepWatchingTagKind(item.status))
            }
            if let range = item.range {
                let axis = rangeBarAxis(range: range, value: item.currentValue)
                RangeBar(
                    lower: range.lowerBound,
                    upper: range.upperBound,
                    min: axis.min,
                    max: axis.max,
                    value: item.currentValue,
                    accessibilityLabel: Text("\(labDisplayName(item.labTestID)) \(item.currentValue.compactFormatted) \(item.unit), \(item.status.label)")
                )
            }
            Text(String(localized: "no supplement — retest \(item.suggestedRetestDate.formatted(date: .abbreviated, time: .omitted))"))
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    private func keepWatchingTagKind(_ status: LabStatus) -> TagKind {
        switch status {
        case .criticalLow, .criticalHigh: .bad
        case .low, .high: .warn
        case .normal: .good
        case .unknown: .warn
        }
    }

    private func labDisplayName(_ labTestID: String) -> String {
        LabCatalog.reference(for: labTestID)?.name ?? labTestID
    }

    // MARK: CTAs

    private func ctaButtons(_ plan: ActionPlan) -> some View {
        VStack(spacing: 10) {
            Button {
                addPlanAndSetReminders(plan)
            } label: {
                Text(isAddingPlan ? "Adding…" : "Add Plan + Set Reminders")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(plan.items.isEmpty || isAddingPlan)

            Button {
                if premiumStore.isPremium {
                    showingAIChat = true
                } else {
                    showingPaywall = true
                }
            } label: {
                Label("Ask About This Plan", systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle())

            // Every supplement this screen (or ScanReportView's auto-add)
            // ever creates lives on the dedicated Supplements page — this is
            // the one link this pass adds to reach it from here.
            NavigationLink {
                SupplementsView()
            } label: {
                Label("View Supplements", systemImage: "pills")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    /// Delegates to `SupplementPlanApplier.apply(...)` — the shared helper
    /// extracted from this function's original inline logic so
    /// `ScanReportView`'s automatic post-save supplement add uses the exact
    /// same creation/skip/reminder rule instead of a second copy of it. The
    /// reminder-scheduling closure passed here is unchanged from before the
    /// extraction: request notification authorization, then schedule via the
    /// same `NotificationService.scheduleDailyReminder(id:medicationName:dosage:at:)`
    /// call `MedicationsView.save()` uses. Re-entrancy-guarded the same way
    /// `MedicationsView.save()` guards `isSaving`.
    ///
    /// Unlike the pre-extraction version, a supplement already present
    /// (added by an earlier plan, or by `ScanReportView`'s auto-add) is now
    /// skipped rather than duplicated — `SupplementPlanApplier`'s dedupe
    /// applies here too, so tapping this button twice never creates two rows
    /// for the same supplement.
    private func addPlanAndSetReminders(_ plan: ActionPlan) {
        guard !isAddingPlan, !plan.items.isEmpty else { return }
        isAddingPlan = true

        let created = SupplementPlanApplier.apply(items: plan.items, context: modelContext) { medication in
            let id = medication.reminderID
            let name = medication.name
            let dosage = medication.dosage
            let time = medication.reminderTime ?? .now
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleDailyReminder(id: id, medicationName: name, dosage: dosage, at: time)
                }
            }
        }

        Haptics.success()
        isAddingPlan = false
        let addedCount = created.count
        switch addedCount {
        case 0:
            confirmationMessage = String(localized: "Those supplements are already in your Medications.")
        case 1:
            confirmationMessage = String(localized: "Added 1 supplement to Medications with a daily reminder.")
        default:
            confirmationMessage = String(localized: "Added \(addedCount) supplements to Medications with daily reminders.")
        }
        showingConfirmation = true
    }

    // MARK: - Locked

    private var lockedBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            MicroLabel("Premium")
            Text("Unlock Your Action Plan")
                .font(.headline)
            Text("Gemocode turns your out-of-range lab values into a concrete plan — supplement doses, timing, and when to retest.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingPaywall = true
            } label: {
                Text("Unlock Premium")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unlock your Action Plan with Premium. Gemocode turns your out-of-range lab values into a concrete plan.")
        .accessibilityHint("Double tap Unlock Premium to see plans.")
    }

    // MARK: - Shared helpers

    private func supplementName(_ form: SupplementForm) -> String {
        switch form {
        case .vitaminD3: String(localized: "Vitamin D3")
        case .ironBisglycinate: String(localized: "Iron bisglycinate")
        case .vitaminB12: String(localized: "Vitamin B12")
        case .folate: String(localized: "Folate")
        case .magnesium: String(localized: "Magnesium")
        }
    }

    private func frequencyDisplayName(_ frequency: SupplementFrequency) -> String {
        switch frequency {
        case .daily: String(localized: "daily")
        case .everyOtherDay: String(localized: "every other day")
        }
    }

    private func timingDisplayName(_ timing: SupplementTiming) -> String? {
        switch timing {
        case .none: nil
        case .withFattyMeal: String(localized: "with a fatty meal")
        case .emptyStomachWithVitaminC: String(localized: "empty stomach + vitamin C")
        }
    }

    /// A short, caller-built profile description, identical in spirit to
    /// `ReviewScreen.aiProfileSummary` / `ScanReportView.aiProfileSummary()`
    /// — duplicated per this file's edit-ownership rather than shared.
    private var aiProfileSummary: String? {
        guard let profile = profiles.first else { return nil }
        var parts: [String] = []
        if let age = profile.age {
            parts.append("\(age)-year-old")
        }
        if profile.sex != .unspecified {
            parts.append(profile.sex.displayName.lowercased())
        }
        if !profile.conditions.isEmpty {
            parts.append("conditions: \(profile.conditions)")
        }
        if !profile.allergies.isEmpty {
            parts.append("allergies: \(profile.allergies)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// Axis bounds for a `RangeBar` built around a reference range. Same
    /// padding rule as the identical helper in `ScanReportView.swift` /
    /// `ScannedResultsSheet.swift` / `ReportDetailView.swift` — duplicated
    /// per file rather than lifted into `Support/EditorialComponents.swift`,
    /// which this agent doesn't own.
    private func rangeBarAxis(range: ClosedRange<Double>, value: Double) -> (min: Double, max: Double) {
        let width = range.upperBound - range.lowerBound
        let pad = width > 0 ? width * 0.35 : max(abs(range.upperBound), 1) * 0.2
        let lower = Swift.min(range.lowerBound - pad, value - pad * 0.15)
        let upper = Swift.max(range.upperBound + pad, value + pad * 0.15)
        return (lower, upper)
    }
}
