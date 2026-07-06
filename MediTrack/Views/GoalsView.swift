import SwiftUI
import SwiftData

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
                }
                Text(Units.formatted(goal.targetValue, for: goal.type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let progress = goal.progress(latest: latest) {
                ProgressView(value: progress)
                    .tint(goal.isAchieved(latest: latest) ? .green : .teal)
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
            Form {
                Section {
                    Picker("Vital", selection: $type) {
                        ForEach(goalTypes) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    TextField("Target (\(Units.label(for: type)))", text: $targetText)
                        .keyboardType(.decimalPad)
                    if let latestValue {
                        LabeledContent("Current", value: Units.formatted(latestValue, for: type))
                    }
                    Toggle("Target date", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("By", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Progress is measured from your current value to the target as new readings come in.")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle("New Goal")
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
