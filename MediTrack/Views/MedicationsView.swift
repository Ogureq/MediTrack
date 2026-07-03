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
                        .buttonStyle(.borderedProminent)
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
                                        } label: {
                                            Label("Mark as Ended", systemImage: "checkmark.circle")
                                        }
                                    }
                            }
                            .onDelete { offsets in
                                delete(offsets, from: activeMedications)
                            }
                        }
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
                    }
                }
            }
        }
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
            modelContext.delete(list[index])
        }
    }
}

struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(medication.name)
                .font(.subheadline.weight(.semibold))
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
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
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
        modelContext.insert(medication)
        dismiss()
    }
}
