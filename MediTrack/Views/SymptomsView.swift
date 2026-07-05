import SwiftUI
import SwiftData

struct SymptomsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SymptomEntry.date, order: .reverse) private var symptoms: [SymptomEntry]

    @State private var showingAdd = false

    var body: some View {
        Group {
            if symptoms.isEmpty {
                ContentUnavailableView {
                    Label("No Symptoms Logged", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Log how you feel — patterns in your symptom journal help you and your doctor spot what matters.")
                } actions: {
                    Button("Log a Symptom") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                }
            } else {
                List {
                    Section {
                        ForEach(symptoms) { entry in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !entry.notes.isEmpty {
                                        Text(entry.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                StatusPill(
                                    text: "\(entry.severity)/10",
                                    color: severityColor(entry.severity)
                                )
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete(perform: delete)
                    } footer: {
                        Text("Severity is your own 1–10 rating. Entries from the last two weeks feed into your Health Review.")
                    }
                    .listRowBackground(GlassRowBackground())
                    .listRowSeparator(.hidden)
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Symptoms")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAdd) { AddSymptomSheet() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(symptoms[index])
        }
    }
}

func severityColor(_ severity: Int) -> Color {
    switch severity {
    case ..<4: .green
    case 4...6: .orange
    default: .red
    }
}

struct AddSymptomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var severity = 5.0
    @State private var date = Date.now
    @State private var notes = ""

    private static let commonSymptoms = [
        "Headache", "Fatigue", "Fever", "Cough", "Nausea",
        "Dizziness", "Back Pain", "Insomnia", "Sore Throat", "Anxiety",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symptom (e.g. Headache)", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.commonSymptoms, id: \.self) { symptom in
                                Button {
                                    name = symptom
                                } label: {
                                    Text(symptom)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .overlay(
                                            Capsule().strokeBorder(
                                                name == symptom
                                                    ? Color.accentColor.opacity(0.7)
                                                    : Color.primary.opacity(0.1),
                                                lineWidth: 1
                                            )
                                        )
                                        .foregroundStyle(name == symptom ? Color.accentColor : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section {
                    HStack {
                        Text("Severity")
                        Spacer()
                        Text("\(Int(severity))/10")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(severityColor(Int(severity)))
                            .contentTransition(.numericText())
                    }
                    Slider(value: $severity, in: 1...10, step: 1)
                        .tint(severityColor(Int(severity)))
                    DatePicker("When", selection: $date, in: ...Date.now)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle("Log Symptom")
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
        modelContext.insert(SymptomEntry(
            name: name.trimmingCharacters(in: .whitespaces),
            severity: Int(severity),
            date: date,
            notes: notes.trimmingCharacters(in: .whitespaces)
        ))
        Haptics.success()
        dismiss()
    }
}
