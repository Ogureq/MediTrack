import SwiftUI
import SwiftData
import UIKit

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HealthGoal.createdAt, order: .reverse) private var goals: [HealthGoal]
    @Query private var vitals: [VitalSample]

    @State private var showingAdd = false

    private var activeGoals: [HealthGoal] { goals.filter(\.isActive) }
    private var completedGoals: [HealthGoal] { goals.filter { !$0.isActive } }

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
                List {
                    if !activeGoals.isEmpty {
                        Section("Active") {
                            ForEach(activeGoals) { goal in
                                GoalProgressRow(goal: goal, latest: latestValue(for: goal.type))
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
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !completedGoals.isEmpty {
                        Section("Completed") {
                            ForEach(completedGoals) { goal in
                                GoalProgressRow(goal: goal, latest: latestValue(for: goal.type))
                            }
                            .onDelete { offsets in
                                delete(offsets, from: completedGoals)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Goals")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add goal")
        }
        .sheet(isPresented: $showingAdd) { AddGoalSheet() }
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
                    StatusPill(text: "Achieved", color: .green)
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

    /// Rotating two-color gradient pairs for the progress bar — cycles
    /// deterministically per goal and carries no semantic meaning.
    private static let gradientPairs: [(Color, Color)] = [
        (Color(red: 0x40 / 255, green: 0xC8 / 255, blue: 0xE0 / 255), Color(red: 0x7E / 255, green: 0xE8 / 255, blue: 0xB0 / 255)), // teal → mint
        (Color(red: 0xA8 / 255, green: 0x96 / 255, blue: 0xFF / 255), Color(red: 0x78 / 255, green: 0xBE / 255, blue: 0xFF / 255)), // purple → blue
        (Color(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x66 / 255), Color(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x66 / 255)), // orange → yellow
    ]

    private var progress: Double? { goal.progress(latest: latest) }
    private var achieved: Bool { goal.isAchieved(latest: latest) }

    /// Stable per-goal gradient pair — keyed on fields that don't change
    /// after creation, so a goal keeps the same colors across app launches.
    private var pair: (Color, Color) {
        let key = "\(goal.typeRaw)|\(goal.createdAt.timeIntervalSince1970)"
        return Self.gradientPairs[stableIndex(key, count: Self.gradientPairs.count)]
    }

    private var barColors: [Color] { achieved ? [.green, .mint] : [pair.0, pair.1] }
    private var glowColor: Color { achieved ? Color.green.opacity(0.4) : pair.0.opacity(0.4) }

    private var progressLine: String {
        let unit = Units.label(for: goal.type)
        switch (goal.startValue, latest) {
        case let (start?, latest?):
            return "\(Units.display(start, for: goal.type).compactFormatted) → \(Units.display(latest, for: goal.type).compactFormatted) \(unit)"
        case let (nil, latest?):
            return "Currently \(Units.display(latest, for: goal.type).compactFormatted) \(unit)"
        case let (start?, nil):
            return "Started at \(Units.display(start, for: goal.type).compactFormatted) \(unit)"
        case (nil, nil):
            return "No readings yet"
        }
    }

    private var dueText: String {
        if let targetDate = goal.targetDate {
            return "Target: \(targetDate.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return "Ongoing"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(goal.type.displayName, systemImage: goal.type.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if achieved {
                    StatusPill(text: "Achieved", color: .green)
                } else if let progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(pair.0)
                }
            }

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: barColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                            .shadow(color: glowColor, radius: 6, x: 0, y: 0)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }

            HStack {
                Text(progressLine)
                Spacer(minLength: 8)
                Text(dueText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Deterministic (non-randomized) index into a fixed-size palette. Swift's
/// `String.hashValue` uses a per-process random seed, so it would make the
/// assigned gradient drift between app launches for the same goal — this
/// stays stable for the life of the record.
private func stableIndex(_ text: String, count: Int) -> Int {
    var hash = 5381
    for scalar in text.unicodeScalars {
        hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
    }
    return abs(hash) % count
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
    let title: String
    let subtitle: String

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
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Tappable capsule chip used to fill a field without typing.
private struct SuggestionChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

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
                .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .background(
                        Circle().fill(isSelected ? AnyShapeStyle(Glass.accentGradient) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .overlay(Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1))
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
