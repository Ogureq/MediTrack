import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]

    @State private var showingAdd = false

    private var activeMedications: [Medication] {
        medications.filter(\.isActive)
    }

    private var pastMedications: [Medication] {
        medications.filter { !$0.isActive }
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
                    if !activeMedications.isEmpty {
                        Section("Active") {
                            ForEach(activeMedications) { medication in
                                MedicationRow(medication: medication)
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
                                MedicationRow(medication: medication)
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
        }
        .sheet(isPresented: $showingAdd) { AddMedicationSheet() }
    }

    private func delete(_ offsets: IndexSet, from list: [Medication]) {
        for index in offsets {
            NotificationService.cancelReminder(id: list[index].reminderID)
            modelContext.delete(list[index])
        }
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
    }
}

struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency = ""
    @State private var purpose = ""
    @State private var notes = ""
    @State private var startDate = Date.now
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now

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
            .navigationTitle("Add Medication")
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
        let medication = Medication(
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosage.trimmingCharacters(in: .whitespaces),
            frequency: frequency.trimmingCharacters(in: .whitespaces),
            purpose: purpose.trimmingCharacters(in: .whitespaces),
            notes: notes,
            startDate: startDate
        )
        medication.reminderEnabled = reminderEnabled
        medication.reminderTime = reminderEnabled ? reminderTime : nil
        modelContext.insert(medication)
        if reminderEnabled {
            let id = medication.reminderID
            let name = medication.name
            let dosage = medication.dosage
            let time = reminderTime
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleDailyReminder(
                        id: id,
                        medicationName: name,
                        dosage: dosage,
                        at: time
                    )
                }
            }
        }
        Haptics.success()
        dismiss()
    }
}
