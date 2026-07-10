import SwiftUI
import SwiftData

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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $name)
                    TextField("Dosage (e.g. 500 mg)", text: $dosage)
                    TextField("Frequency (e.g. twice daily)", text: $frequency)
                    TextField("Purpose (e.g. blood pressure)", text: $purpose)
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text("MediTrack sends a local notification every day at this time while the medication is active.")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle(existingMedication == nil ? "Add Medication" : "Edit Medication")
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
