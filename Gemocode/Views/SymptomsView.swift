import SwiftUI
import SwiftData
import UIKit

struct SymptomsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \SymptomEntry.date, order: .reverse) private var symptoms: [SymptomEntry]

    @State private var showingAdd = false

    /// Splits the journal into "This Week" and "Earlier" the way 7o's ledger
    /// is laid out — both derived from the entries' own `date`, nothing new
    /// is computed or inferred about them.
    private var recentCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    private var thisWeekSymptoms: [SymptomEntry] {
        symptoms.filter { $0.date >= recentCutoff }
    }

    private var earlierSymptoms: [SymptomEntry] {
        symptoms.filter { $0.date < recentCutoff }
    }

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
                    if !thisWeekSymptoms.isEmpty {
                        Section {
                            ForEach(thisWeekSymptoms) { entry in
                                SymptomLogRow(entry: entry)
                                    .ledgerRow()
                            }
                            .onDelete { offsets in
                                delete(offsets, from: thisWeekSymptoms)
                            }
                        } header: {
                            MicroLabel("This Week")
                        } footer: {
                            if earlierSymptoms.isEmpty {
                                Text("Severity is your own 1–10 rating. Entries from the last two weeks feed into your Health Review.")
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !earlierSymptoms.isEmpty {
                        Section {
                            ForEach(earlierSymptoms) { entry in
                                SymptomLogRow(entry: entry)
                                    .ledgerRow()
                            }
                            .onDelete { offsets in
                                delete(offsets, from: earlierSymptoms)
                            }
                        } header: {
                            MicroLabel("Earlier")
                        } footer: {
                            Text("Severity is your own 1–10 rating. Entries from the last two weeks feed into your Health Review.")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .ambientScreen()
        .navigationTitle("Symptoms")
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
            .accessibilityLabel("Log symptom")
        }
        .sheet(isPresented: $showingAdd) { AddSymptomSheet() }
    }

    private func delete(_ offsets: IndexSet, from list: [SymptomEntry]) {
        for index in offsets {
            modelContext.delete(list[index])
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

/// One entry in the symptom log: name + severity pill up top, a 10-segment
/// severity meter, then a note/when caption row. Reuses `severityColor(_:)`
/// (the same thresholds the severity slider and old pill used) for the pill,
/// the filled dots, and the accessibility summary, so all three never
/// disagree about what counts as mild/moderate/severe.
private struct SymptomLogRow: View {
    let entry: SymptomEntry

    @Environment(\.colorScheme) private var colorScheme

    private var tagKind: TagKind {
        switch entry.severity {
        case ..<4: .good
        case 4...6: .warn
        default: .bad
        }
    }

    private var barColor: Color {
        switch tagKind {
        case .good: Editorial.tagGood(colorScheme)
        case .warn: Editorial.tagWarn(colorScheme)
        case .bad: Editorial.tagBad(colorScheme)
        }
    }

    private var severityLabel: LocalizedStringKey {
        switch tagKind {
        case .good: "Mild"
        case .warn: "Moderate"
        case .bad: "Severe"
        }
    }

    private var accessibilityText: String {
        var parts = ["\(entry.name), severity \(entry.severity) out of 10"]
        if !entry.notes.isEmpty { parts.append(entry.notes) }
        parts.append(entry.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                EditorialTag(severityLabel, kind: tagKind)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Editorial.hairline(colorScheme))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(entry.severity) / 10)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Editorial.muted(colorScheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
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
    /// Guards `save()` against a double tap firing two inserts before the
    /// sheet has dismissed — checked and set at the top of `save()`, and
    /// mirrored onto the Save button's `disabled` state.
    @State private var isSaving = false

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
                            .font(.system(size: 52, weight: .bold))
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
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

/// Light selection feedback for chip taps — UIHelpers only defines the
/// success notification haptic, so this stays local to each sheet file.
private enum SheetHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
