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
                                GoalRow(goal: goal, latest: latestValue(for: goal.type))
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
                                GoalRow(goal: goal, latest: latestValue(for: goal.type))
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
                        .disabled(parsedTarget == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func save() {
        guard let target = parsedTarget else { return }
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
                .font(.title2.weight(.semibold))
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
                    .font(.title3)
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
