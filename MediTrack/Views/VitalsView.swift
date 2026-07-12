import SwiftUI
import SwiftData
import Charts
import UIKit

struct VitalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VitalSample.date, order: .reverse) private var vitals: [VitalSample]

    @State private var selectedType: VitalType
    @State private var showingAdd = false

    init(initialType: VitalType = .weight) {
        _selectedType = State(initialValue: initialType)
    }

    private var samples: [VitalSample] {
        vitals.filter { $0.type == selectedType }
    }

    var body: some View {
        List {
            Section {
                Picker("Vital", selection: $selectedType) {
                    ForEach(VitalType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                if samples.count >= 2 {
                    chart
                        .frame(height: 200)
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section("History") {
                if samples.isEmpty {
                    Text("No readings yet. Tap + to add your first \(selectedType.displayName.lowercased()) reading.")
                        .foregroundStyle(.secondary)
                }
                ForEach(samples) { sample in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            if !sample.note.isEmpty {
                                Text(sample.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(sample.formattedValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete(perform: deleteSamples)
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
        .ambientScreen()
        .navigationTitle("Vitals")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add vital")
        }
        .sheet(isPresented: $showingAdd) {
            AddVitalSheet(initialType: selectedType)
        }
    }

    private var chart: some View {
        let ascending = samples.sorted { $0.date < $1.date }
        return Chart {
            if let healthyRange = selectedType.healthyRange {
                let range = Units.displayRange(healthyRange, for: selectedType)
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(.green.opacity(0.08))
            }
            ForEach(ascending) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: selectedType)),
                    series: .value("Series", "primary")
                )
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: selectedType))
                )
            }
            if selectedType == .bloodPressure {
                ForEach(ascending.filter { $0.secondaryValue != nil }) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Diastolic", sample.secondaryValue ?? 0),
                        series: .value("Series", "secondary")
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartYAxisLabel(Units.label(for: selectedType))
        .accessibilityLabel("\(selectedType.displayName) trend chart")
    }

    private func deleteSamples(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(samples[index])
        }
    }
}

struct AddVitalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("health.writeBackEnabled") private var healthWriteBackEnabled = false

    @State private var type: VitalType
    @State private var valueText = ""
    @State private var secondaryText = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var showingDetails = false

    init(initialType: VitalType = .weight) {
        _type = State(initialValue: initialType)
    }

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedSecondary: Double? {
        Double(secondaryText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard parsedValue != nil else { return false }
        if type.usesSecondaryValue {
            return parsedSecondary != nil
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: type.systemImage,
                        tint: .blue,
                        title: "Add Vital",
                        subtitle: "Log a new \(type.displayName.lowercased()) reading."
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Type")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(VitalType.allCases) { option in
                                    VitalTypeChip(type: option, isSelected: type == option) {
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

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel(type.usesSecondaryValue ? "Systolic (\(type.unit))" : "Value (\(Units.label(for: type)))")
                        TextField(
                            type.usesSecondaryValue ? "Systolic (\(type.unit))" : "Value (\(Units.label(for: type)))",
                            text: $valueText
                        )
                        .font(.title3.weight(.semibold))
                        .keyboardType(.decimalPad)

                        if type.usesSecondaryValue {
                            Divider().opacity(0.5)
                            SheetFieldLabel("Diastolic (\(type.unit))")
                            TextField("Diastolic (\(type.unit))", text: $secondaryText)
                                .font(.title3.weight(.semibold))
                                .keyboardType(.decimalPad)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Date")
                        DatePicker("Date", selection: $date)
                            .labelsHidden()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 10) {
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
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func save() {
        guard let value = parsedValue else { return }
        let sample = VitalSample(
            type: type,
            value: Units.canonical(value, for: type),
            secondaryValue: type.usesSecondaryValue ? parsedSecondary : nil,
            date: date,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(sample)
        Haptics.success()
        if healthWriteBackEnabled && HealthKitService.isWritable(type) {
            writeToHealth(sample)
        }
        dismiss()
    }

    /// Best-effort mirror of a newly logged vital into Apple Health. The
    /// local save has already succeeded, so any failure here is silent.
    private func writeToHealth(_ sample: VitalSample) {
        Task {
            do {
                try await HealthKitService.requestWriteAuthorization()
                try await HealthKitService.write(sample: sample)
            } catch {
                // Non-fatal: the vital is already saved locally.
            }
        }
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

/// Horizontally scrolling icon chip used to pick the vital type without a
/// system Picker wheel.
private struct VitalTypeChip: View {
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
            .frame(width: 72)
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
