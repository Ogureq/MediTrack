import SwiftUI
import SwiftData
import UIKit

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]

    @State private var showingAdd = false
    @State private var editingMedication: Medication?

    private var activeMedications: [Medication] {
        medications.filter(\.isActive)
    }

    private var pastMedications: [Medication] {
        medications.filter { !$0.isActive }
    }

    private var interactions: [DrugInteraction] {
        MedicationInteractions.check(medicationNames: activeMedications.map(\.name))
    }

    var body: some View {
        Group {
            if medications.isEmpty {
                ContentUnavailableView {
                    Label("No Medications", systemImage: "pills")
                } description: {
                    Text("Track the medications you take, with dosage and schedule.")
                } actions: {
                    Button("Add Medication") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                }
            } else {
                List {
                    if !interactions.isEmpty {
                        Section {
                            ForEach(interactions) { interaction in
                                InteractionRow(interaction: interaction)
                            }
                        } header: {
                            Label("Possible Interactions", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } footer: {
                            Text(MedicationInteractions.disclaimer)
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !activeMedications.isEmpty {
                        Section("Active") {
                            ForEach(activeMedications) { medication in
                                Button {
                                    editingMedication = medication
                                } label: {
                                    MedicationRow(medication: medication)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        medication.endDate = .now
                                        NotificationService.cancelReminder(id: medication.reminderID)
                                    } label: {
                                        Label("Mark as Ended", systemImage: "checkmark.circle")
                                    }
                                }
                            }
                            .onDelete { offsets in
                                delete(offsets, from: activeMedications)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !pastMedications.isEmpty {
                        Section("Past") {
                            ForEach(pastMedications) { medication in
                                Button {
                                    editingMedication = medication
                                } label: {
                                    MedicationRow(medication: medication)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: pastMedications)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Medications")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add medication")
        }
        .sheet(isPresented: $showingAdd) { AddMedicationSheet() }
        .sheet(item: $editingMedication) { medication in
            AddMedicationSheet(medication: medication)
        }
    }

    private func delete(_ offsets: IndexSet, from list: [Medication]) {
        for index in offsets {
            NotificationService.cancelReminder(id: list[index].reminderID)
            modelContext.delete(list[index])
        }
    }
}

struct InteractionRow: View {
    let interaction: DrugInteraction

    private var color: Color {
        switch interaction.severity {
        case .major: .red
        case .moderate: .orange
        case .minor: .yellow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: interaction.severity.systemImage)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text("\(interaction.drugA) + \(interaction.drugB)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusPill(text: interaction.severity.displayName, color: color)
            }
            Text(interaction.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(interaction.recommendation, systemImage: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(medication.name)
                    .font(.subheadline.weight(.semibold))
                if medication.isActive, medication.reminderEnabled, let time = medication.reminderTime {
                    Label(time.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            if !medication.dosage.isEmpty || !medication.frequency.isEmpty {
                Text([medication.dosage, medication.frequency].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !medication.purpose.isEmpty {
                Text(medication.purpose)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                Text("Since \(medication.startDate.formatted(date: .abbreviated, time: .omitted))")
                if let endDate = medication.endDate {
                    Text("– \(endDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existingMedication: Medication?

    @State private var name: String
    @State private var dosage: String
    @State private var frequency: String
    @State private var purpose: String
    @State private var notes: String
    @State private var startDate: Date
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var showingDetails: Bool

    private static let frequencyOptions = [
        "Once daily", "Twice daily", "Every morning", "Every night", "As needed",
    ]
    private static let dosageUnits = ["mg", "mcg", "ml", "tablets"]

    init(medication: Medication? = nil) {
        existingMedication = medication
        _name = State(initialValue: medication?.name ?? "")
        _dosage = State(initialValue: medication?.dosage ?? "")
        _frequency = State(initialValue: medication?.frequency ?? "")
        _purpose = State(initialValue: medication?.purpose ?? "")
        _notes = State(initialValue: medication?.notes ?? "")
        _startDate = State(initialValue: medication?.startDate ?? .now)
        _reminderEnabled = State(initialValue: medication?.reminderEnabled ?? false)
        _reminderTime = State(initialValue: medication?.reminderTime
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
        _showingDetails = State(initialValue: !(medication?.purpose ?? "").isEmpty || !(medication?.notes ?? "").isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: "pills.fill",
                        tint: .teal,
                        title: existingMedication == nil ? "Add Medication" : "Edit Medication",
                        subtitle: "Track dosage, schedule, and reminders."
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel("Name")
                        TextField("e.g. Lisinopril", text: $name)
                            .font(.body)

                        Divider().opacity(0.5)

                        SheetFieldLabel("Dosage")
                        TextField("e.g. 500 mg", text: $dosage)
                            .font(.body)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.dosageUnits, id: \.self) { unit in
                                    SuggestionChip(label: unit, isSelected: false) {
                                        appendUnit(unit)
                                    }
                                }
                            }
                        }

                        Divider().opacity(0.5)

                        SheetFieldLabel("Frequency")
                        TextField("e.g. Twice daily", text: $frequency)
                            .font(.body)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.frequencyOptions, id: \.self) { option in
                                    SuggestionChip(label: option, isSelected: frequency == option) {
                                        frequency = option
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Start Date")
                        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Daily reminder", isOn: $reminderEnabled.animation())
                            .font(.body.weight(.semibold))
                        if reminderEnabled {
                            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        }
                        Text("MediTrack sends a local notification every day at this time while the medication is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 14) {
                            SheetFieldLabel("Purpose")
                            TextField("e.g. Blood pressure", text: $purpose)
                                .font(.body)

                            SheetFieldLabel("Notes")
                            TextField("Notes", text: $notes, axis: .vertical)
                                .font(.body)
                                .lineLimit(2...4)
                        }
                        .padding(.top, 12)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Replaces any existing unit suffix on the dosage field with the tapped one.
    private func appendUnit(_ unit: String) {
        SheetHaptics.selection()
        let numberPart = dosage.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        dosage = numberPart.isEmpty ? unit : "\(numberPart) \(unit)"
    }

    private func save() {
        let medication: Medication
        if let existingMedication {
            medication = existingMedication
            medication.name = name.trimmingCharacters(in: .whitespaces)
            medication.dosage = dosage.trimmingCharacters(in: .whitespaces)
            medication.frequency = frequency.trimmingCharacters(in: .whitespaces)
            medication.purpose = purpose.trimmingCharacters(in: .whitespaces)
            medication.notes = notes
            medication.startDate = startDate
        } else {
            medication = Medication(
                name: name.trimmingCharacters(in: .whitespaces),
                dosage: dosage.trimmingCharacters(in: .whitespaces),
                frequency: frequency.trimmingCharacters(in: .whitespaces),
                purpose: purpose.trimmingCharacters(in: .whitespaces),
                notes: notes,
                startDate: startDate
            )
            modelContext.insert(medication)
        }
        medication.reminderEnabled = reminderEnabled
        medication.reminderTime = reminderEnabled ? reminderTime : nil

        // Reschedule from scratch so edits never leave a stale notification.
        NotificationService.cancelReminder(id: medication.reminderID)
        if reminderEnabled && medication.isActive {
            let id = medication.reminderID
            let medicationName = medication.name
            let dosageText = medication.dosage
            let time = reminderTime
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleDailyReminder(
                        id: id,
                        medicationName: medicationName,
                        dosage: dosageText,
                        at: time
                    )
                }
            }
        }
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

/// Light selection feedback for chip taps — UIHelpers only defines the
/// success notification haptic, so this stays local to each sheet file.
private enum SheetHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
