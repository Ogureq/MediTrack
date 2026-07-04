import SwiftUI
import SwiftData
import Charts

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
        }
        .sheet(isPresented: $showingAdd) {
            AddVitalSheet(initialType: selectedType)
        }
    }

    private var chart: some View {
        let ascending = samples.sorted { $0.date < $1.date }
        return Chart {
            if let range = selectedType.healthyRange {
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(.green.opacity(0.08))
            }
            ForEach(ascending) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", sample.value),
                    series: .value("Series", "primary")
                )
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", sample.value)
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
        .chartYAxisLabel(selectedType.unit)
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

    @State private var type: VitalType
    @State private var valueText = ""
    @State private var secondaryText = ""
    @State private var date = Date.now
    @State private var note = ""

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
            Form {
                Section {
                    Picker("Vital", selection: $type) {
                        ForEach(VitalType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    TextField(
                        type.usesSecondaryValue ? "Systolic (\(type.unit))" : "Value (\(type.unit))",
                        text: $valueText
                    )
                    .keyboardType(.decimalPad)
                    if type.usesSecondaryValue {
                        TextField("Diastolic (\(type.unit))", text: $secondaryText)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $date)
                    TextField("Note (optional)", text: $note)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle("Add Vital")
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
    }

    private func save() {
        guard let value = parsedValue else { return }
        let sample = VitalSample(
            type: type,
            value: value,
            secondaryValue: type.usesSecondaryValue ? parsedSecondary : nil,
            date: date,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(sample)
        dismiss()
    }
}
