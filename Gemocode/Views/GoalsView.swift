import SwiftUI
import SwiftData
import UIKit

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \HealthGoal.createdAt, order: .reverse) private var goals: [HealthGoal]
    @Query private var vitals: [VitalSample]
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

    @State private var showingAdd = false

    /// Every catalog-tracked lab's re-test status, per `RetestSchedule.items`
    /// — cached the same way `RetestScheduleView`/`DashboardView` cache it
    /// (`.task(id: retestSignature)`), so `labLinkID(for:)`'s lookups and the
    /// footer's `RetestSchedule.nextDraw` call never re-flatten every
    /// report's lab results per render.
    @State private var retestItems: [RetestItem] = []

    private var retestSignature: String {
        "\(reports.count)-\(reports.reduce(0) { $0 + $1.labResults.count })"
    }

    private var activeGoals: [HealthGoal] { goals.filter(\.isActive) }
    private var completedGoals: [HealthGoal] { goals.filter { !$0.isActive } }

    // MARK: - Goal -> lab linkage (computed only, no schema change)
    //
    // `HealthGoal` has no free-text title, only `type: VitalType` and a
    // `note`. Only `bloodGlucose` has a natural, same-unit `LabCatalog`
    // correspondent (fastingGlucose, both mg/dL) to fall back to directly;
    // every other goal's link (if any) comes from matching `note` against
    // this keyword table — English + a small Russian set, longest-token
    // wins, same mechanics as `MedicationLabLinks.classKey(for:)`.
    private static let goalLabKeywordTokens: [(token: String, labID: String)] = [
        ("vitamin d", "vitaminD"), ("витамин d", "vitaminD"), ("витамин д", "vitaminD"),
        ("hba1c", "hba1c"), ("hb a1c", "hba1c"), ("гликированный гемоглобин", "hba1c"),
        ("ldl", "ldlCholesterol"), ("лпнп", "ldlCholesterol"),
        ("hdl", "hdlCholesterol"), ("лпвп", "hdlCholesterol"),
        ("cholesterol", "totalCholesterol"), ("холестерин", "totalCholesterol"),
        ("triglyceride", "triglycerides"), ("триглицерид", "triglycerides"),
        ("ferritin", "ferritin"), ("ферритин", "ferritin"),
        ("tsh", "tsh"), ("ттг", "tsh"),
        ("creatinine", "creatinine"), ("креатинин", "creatinine"),
        ("uric acid", "uricAcid"), ("мочевая кислота", "uricAcid"),
        ("magnesium", "magnesium"), ("магний", "magnesium"),
        ("potassium", "potassium"), ("калий", "potassium"),
        ("glucose", "fastingGlucose"), ("глюкоз", "fastingGlucose"),
    ]

    /// The `LabCatalog` id this goal is checked against, or `nil` when it
    /// has none — a plain vital-only goal (e.g. weight, sleep), which keeps
    /// its existing manual progress caption.
    private func labLinkID(for goal: HealthGoal) -> String? {
        let lower = goal.note.lowercased()
        var best: (token: String, labID: String)?
        for entry in Self.goalLabKeywordTokens where lower.contains(entry.token) {
            if best == nil || entry.token.count > best!.token.count {
                best = entry
            }
        }
        if let best { return best.labID }
        if goal.type == .bloodGlucose { return "fastingGlucose" }
        return nil
    }

    /// The cached `RetestItem` for this goal's linked lab, or `nil` when the
    /// goal isn't lab-linked, or that lab has never been tested (so
    /// `RetestSchedule` has no due date to report yet).
    private func linkedRetestItem(for goal: HealthGoal) -> RetestItem? {
        guard let labID = labLinkID(for: goal) else { return nil }
        return retestItems.first { $0.id.caseInsensitiveCompare(labID) == .orderedSame }
    }

    /// "checked at %@ draw/retest" caption for a lab-linked goal, or `nil`
    /// for an unlinked goal (which keeps its manual `dueText` caption).
    private func retestCaption(for goal: HealthGoal) -> String? {
        guard let item = linkedRetestItem(for: goal) else { return nil }
        let dateText = item.dueDate.formatted(.dateTime.month(.abbreviated).day())
        return String(format: String(localized: "checked at %@ draw/retest"), dateText)
    }

    /// "All N goals get verified by the [date] draw — no extra tests
    /// needed." — shown ONLY when there's at least one lab-linked active
    /// goal AND every one of those goals' labs falls inside the SAME
    /// `RetestSchedule.nextDraw` bundle; omitted otherwise (e.g. two linked
    /// goals due on different, non-bundled draws) so this never overstates
    /// what a single visit actually covers.
    private var drawBundleFooterText: String? {
        let linkedItems = activeGoals.compactMap(linkedRetestItem(for:))
        guard !linkedItems.isEmpty, let bundle = RetestSchedule.nextDraw(items: retestItems, now: .now) else {
            return nil
        }
        let bundleIDs = Set(bundle.items.map(\.id))
        guard linkedItems.allSatisfy({ bundleIDs.contains($0.id) }) else { return nil }

        let dateText = bundle.date.formatted(.dateTime.month(.abbreviated).day())
        if linkedItems.count == 1 {
            return String(format: String(localized: "1 goal gets verified by the %@ draw — no extra tests needed."), dateText)
        }
        return String(
            format: String(localized: "All %1$lld goals get verified by the %2$@ draw — no extra tests needed."),
            linkedItems.count, dateText
        )
    }

    var body: some View {
        Group {
            if goals.isEmpty {
                ContentUnavailableView {
                    Label("No Goals", systemImage: "target")
                } description: {
                    Text("Set a target for a vital — like a goal weight or nightly sleep — and track your progress toward it.")
                } actions: {
                    Button("Add Goal") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                }
            } else {
                // The footer's `RetestSchedule.nextDraw` walk plus every
                // row's `linkedRetestItem(for:)` lookup all read the same
                // cached `retestItems` — nothing here re-flattens reports.
                let footerText = drawBundleFooterText
                List {
                    Section {
                        Text("Each goal is checked automatically by its lab or vital.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Editorial.muted(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if !activeGoals.isEmpty {
                        Section {
                            ForEach(activeGoals) { goal in
                                GoalProgressRow(
                                    goal: goal,
                                    latest: latestValue(for: goal.type),
                                    retestCaption: retestCaption(for: goal)
                                )
                                    .ledgerRow()
                                    .contextMenu {
                                        Button {
                                            goal.isActive = false
                                        } label: {
                                            Label("Mark Completed", systemImage: "checkmark.circle")
                                        }
                                    }
                            }
                            .onDelete { offsets in
                                delete(offsets, from: activeGoals)
                            }
                        } header: {
                            MicroLabel("Active")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !completedGoals.isEmpty {
                        Section {
                            ForEach(completedGoals) { goal in
                                GoalProgressRow(
                                    goal: goal,
                                    latest: latestValue(for: goal.type),
                                    retestCaption: retestCaption(for: goal)
                                )
                                    .ledgerRow()
                            }
                            .onDelete { offsets in
                                delete(offsets, from: completedGoals)
                            }
                        } header: {
                            MicroLabel("Completed")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if let footerText {
                        Section {
                            GoalsDrawBundleFooter(text: footerText)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .ambientScreen()
        .navigationTitle("Goals")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
            }
            .accessibilityLabel("Add goal")
        }
        .sheet(isPresented: $showingAdd) { AddGoalSheet() }
        .task(id: retestSignature) {
            retestItems = RetestSchedule.items(reports: reports, now: .now)
        }
    }

    private func latestValue(for type: VitalType) -> Double? {
        vitals.filter { $0.type == type }.max { $0.date < $1.date }?.value
    }

    private func delete(_ offsets: IndexSet, from list: [HealthGoal]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
}

struct GoalRow: View {
    let goal: HealthGoal
    let latest: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(goal.type.displayName, systemImage: goal.type.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if goal.isAchieved(latest: latest) {
                    StatusPill(text: String(localized: "Achieved"), color: .green)
                }
            }
            HStack(spacing: 4) {
                if let latest {
                    Text(Units.formatted(latest, for: goal.type))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(Units.formatted(goal.targetValue, for: goal.type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let progress = goal.progress(latest: latest) {
                ProgressView(value: progress)
                    .tint(goal.isAchieved(latest: latest) ? .green : .teal)
                    .accessibilityLabel("Progress toward goal")
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            }
            HStack(spacing: 8) {
                if let targetDate = goal.targetDate {
                    Text("By \(targetDate.formatted(date: .abbreviated, time: .omitted))")
                }
                if !goal.note.isEmpty {
                    Text(goal.note)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Full-card variant of a goal row used only by the dedicated Goals screen's
/// list. `GoalRow` above stays byte-identical because `DashboardView` embeds
/// it directly inside its own compact "Goals" summary card.
private struct GoalProgressRow: View {
    let goal: HealthGoal
    let latest: Double?
    /// "checked at %@ draw/retest" — set only for a goal `GoalsView` matched
    /// to a `LabCatalog` test with a known re-test date; `nil` keeps this
    /// row's existing manual `dueText` caption unchanged.
    var retestCaption: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var progress: Double? { goal.progress(latest: latest) }
    private var achieved: Bool { goal.isAchieved(latest: latest) }

    private var progressAccessibilityLabel: Text? {
        guard let progress else { return nil }
        return Text(String(localized: "Progress toward goal, \(Int((progress * 100).rounded())) percent"))
    }

    private var progressLine: String {
        let unit = Units.label(for: goal.type)
        switch (goal.startValue, latest) {
        case let (start?, latest?):
            return String(
                format: String(localized: "%@ → %@ %@"),
                Units.display(start, for: goal.type).compactFormatted,
                Units.display(latest, for: goal.type).compactFormatted,
                unit
            )
        case let (nil, latest?):
            return String(format: String(localized: "Currently %@ %@"), Units.display(latest, for: goal.type).compactFormatted, unit)
        case let (start?, nil):
            return String(format: String(localized: "Started at %@ %@"), Units.display(start, for: goal.type).compactFormatted, unit)
        case (nil, nil):
            return String(localized: "No readings yet")
        }
    }

    private var dueText: String {
        if let targetDate = goal.targetDate {
            return String(format: String(localized: "Target: %@"), targetDate.formatted(.dateTime.month(.abbreviated).year()))
        }
        return String(localized: "Ongoing")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(goal.type.displayName, systemImage: goal.type.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                if achieved {
                    EditorialTag("Achieved", kind: .good)
                } else if let progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }

            if let progress {
                RangeBar(
                    zones: [
                        (fraction: CGFloat(progress), kind: achieved ? .optimal : .inRange),
                        (fraction: CGFloat(1 - progress), kind: .out),
                    ],
                    marker: CGFloat(progress),
                    accessibilityLabel: progressAccessibilityLabel
                )
            }

            HStack {
                Text(progressLine)
                Spacer(minLength: 8)
                Text(retestCaption ?? dueText)
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Editorial.muted(colorScheme))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Inset-card footer: "All N goals get verified by the [date] draw — no
/// extra tests needed." Only ever built by `GoalsView.drawBundleFooterText`
/// when it's actually true — see that computed property for the honesty
/// gating.
private struct GoalsDrawBundleFooter: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(Editorial.accent(colorScheme))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var vitals: [VitalSample]

    @State private var type: VitalType = .weight
    @State private var targetText = ""
    @State private var hasDeadline = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var note = ""
    @State private var showingDetails = false
    /// Guards `save()` against a double tap firing two inserts before the
    /// sheet has dismissed — checked and set at the top of `save()`, and
    /// mirrored onto the Save button's `disabled` state.
    @State private var isSaving = false

    private struct GoalTemplate {
        let label: String
        let type: VitalType
        let note: String
    }

    private static let templates: [GoalTemplate] = [
        GoalTemplate(label: "Lower Weight", type: .weight, note: "Reach a healthier weight"),
        GoalTemplate(label: "Better Sleep", type: .sleepHours, note: "Get more consistent sleep"),
        GoalTemplate(label: "Lower Glucose", type: .bloodGlucose, note: "Keep blood glucose in range"),
        GoalTemplate(label: "Lower Heart Rate", type: .heartRate, note: "Improve cardiovascular fitness"),
    ]

    private var goalTypes: [VitalType] {
        VitalType.allCases.filter { $0 != .bloodPressure }
    }

    private var parsedTarget: Double? {
        Double(targetText.replacingOccurrences(of: ",", with: "."))
    }

    private var latestValue: Double? {
        vitals.filter { $0.type == type }.max { $0.date < $1.date }?.value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: "target",
                        tint: .teal,
                        title: "New Goal",
                        subtitle: "Set a target and track your progress toward it."
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Quick Start")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.templates, id: \.label) { template in
                                    SuggestionChip(label: template.label, isSelected: false) {
                                        type = template.type
                                        note = template.note
                                        showingDetails = true
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Vital")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(goalTypes) { option in
                                    GoalTypeChip(type: option, isSelected: type == option) {
                                        SheetHaptics.selection()
                                        type = option
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Target (\(Units.label(for: type)))")
                        TextField("Target (\(Units.label(for: type)))", text: $targetText)
                            .font(.title3.weight(.semibold))
                            .keyboardType(.decimalPad)
                        if let latestValue {
                            Divider().opacity(0.5)
                            LabeledContent("Current", value: Units.formatted(latestValue, for: type))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Target date", isOn: $hasDeadline.animation())
                            if hasDeadline {
                                DatePicker("By", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                            }

                            SheetFieldLabel("Note")
                            TextField("Note (optional)", text: $note)
                                .font(.body)
                        }
                        .padding(.top, 12)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    Text("Progress is measured from your current value to the target as new readings come in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .ambientScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedTarget == nil || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func save() {
        guard !isSaving else { return }
        guard let target = parsedTarget else { return }
        isSaving = true
        modelContext.insert(HealthGoal(
            type: type,
            targetValue: Units.canonical(target, for: type),
            startValue: latestValue,
            targetDate: hasDeadline ? targetDate : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        ))
        Haptics.success()
        dismiss()
    }
}

// MARK: - Shared sheet UI

/// Friendly header shown at the top of the add/edit sheet: a tinted icon
/// tile plus a bold title and one-line subtitle, replacing a bare nav title.
private struct SheetHeader: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small uppercase caption used above a field inside a glass block.
private struct SheetFieldLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Tappable capsule chip used to fill a field without typing.
private struct SuggestionChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            SheetHaptics.selection()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .background(isSelected ? Editorial.accent(colorScheme).opacity(0.22) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Editorial.accent(colorScheme).opacity(0.7) : Editorial.controlBorder(colorScheme),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Editorial.accent(colorScheme) : Editorial.ink(colorScheme))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Horizontally scrolling icon chip used to pick the goal's vital type.
private struct GoalTypeChip: View {
    let type: VitalType
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? .white : Editorial.accent(colorScheme))
                    .background(
                        Circle().fill(isSelected ? AnyShapeStyle(Glass.accentGradient) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .overlay(Circle().strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1))
                Text(type.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Light selection feedback for chip taps — UIHelpers only defines the
/// success notification haptic, so this stays local to each sheet file.
private enum SheetHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
