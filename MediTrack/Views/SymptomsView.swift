import SwiftUI
import SwiftData
import UIKit

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
                                .accessibilityLabel("Severity \(entry.severity) out of 10")
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
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
            .accessibilityLabel("Log symptom")
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
    @State private var showingDetails = false

    private static let commonSymptoms = [
        "Headache", "Fatigue", "Nausea", "Dizziness", "Back Pain", "Cough",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: "list.bullet.clipboard",
                        tint: .orange,
                        title: "Log Symptom",
                        subtitle: "Patterns in your journal help spot what matters."
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel("Symptom")
                        TextField("e.g. Headache", text: $name)
                            .font(.body)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.commonSymptoms, id: \.self) { symptom in
                                    SuggestionChip(label: symptom, isSelected: name == symptom) {
                                        name = symptom
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(spacing: 12) {
                        Text("Severity")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(Int(severity))")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(severityColor(Int(severity)))
                            .contentTransition(.numericText())
                            .accessibilityHidden(true)
                        Slider(value: $severity, in: 1...10, step: 1)
                            .tint(severityColor(Int(severity)))
                            .accessibilityLabel("Severity")
                            .accessibilityValue("\(Int(severity)) out of 10")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("When")
                        DatePicker("When", selection: $date, in: ...Date.now)
                            .labelsHidden()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 10) {
                            SheetFieldLabel("Notes")
                            TextField("Notes (optional)", text: $notes, axis: .vertical)
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
