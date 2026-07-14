import SwiftUI
import SwiftData
import Charts
import UIKit

struct VitalsView: View {
    @Query(sort: \VitalSample.date, order: .reverse) private var vitals: [VitalSample]

    @State private var showingAdd = false
    @State private var cards: [VitalCardSummary] = []

    let initialType: VitalType

    init(initialType: VitalType = .weight) {
        self.initialType = initialType
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView {
                    Label("No Vitals Logged", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Log a reading — blood pressure, heart rate, weight, and more — to start tracking trends.")
                } actions: {
                    Button("Log a Vital") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(cards) { card in
                            NavigationLink {
                                VitalTypeDetailView(type: card.type)
                            } label: {
                                VitalMetricCard(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
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
            AddVitalSheet(initialType: initialType)
        }
        .task(id: vitals.count) {
            cards = Self.buildCards(from: vitals)
        }
    }

    /// One card per vital type that has at least one reading, latest-first
    /// within each type's own history so the delta and sparkline reflect
    /// genuine chronological order. Recomputed only when the reading count
    /// changes (see `.task(id:)` above) since grouping every sample on every
    /// render would be wasted work for a screen that mostly just displays.
    private static func buildCards(from vitals: [VitalSample]) -> [VitalCardSummary] {
        VitalType.allCases.compactMap { type in
            let ascending = vitals.filter { $0.type == type }.sorted { $0.date < $1.date }
            guard let latest = ascending.last else { return nil }
            let previous = ascending.dropLast().last
            return VitalCardSummary(
                type: type,
                latest: latest,
                previous: previous,
                sparklinePoints: Array(ascending.suffix(6))
            )
        }
    }
}

// MARK: - Vital grid card

/// Pure summary of one vital type's latest reading, previous reading (for
/// the delta), and a short recent history (for the sparkline). Kept
/// SwiftData-free beyond holding `VitalSample` references so it is cheap to
/// cache in `@State` and diff.
private struct VitalCardSummary: Identifiable {
    let type: VitalType
    let latest: VitalSample
    let previous: VitalSample?
    let sparklinePoints: [VitalSample]

    var id: VitalType { type }
}

/// Per-vital-type tint used for the card label, sparkline stroke, and (when
/// unambiguous) the delta. Distinct hue per type so a dense 2-column grid
/// stays scannable.
private func vitalTint(for type: VitalType) -> Color {
    switch type {
    case .bloodPressure: Color(red: 0x40 / 255, green: 0xC8 / 255, blue: 0xE0 / 255)
    case .heartRate: Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x88 / 255)
    case .oxygenSaturation: Color(red: 0x78 / 255, green: 0xBE / 255, blue: 0xFF / 255)
    case .weight: Color(red: 0x7E / 255, green: 0xE8 / 255, blue: 0xB0 / 255)
    case .temperature: Color(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x66 / 255)
    case .bloodGlucose: Color(red: 0xA8 / 255, green: 0x96 / 255, blue: 0xFF / 255)
    case .respiratoryRate: Color(red: 0x63 / 255, green: 0xE6 / 255, blue: 0xBE / 255)
    case .sleepHours: Color(red: 0x8E / 255, green: 0x8C / 255, blue: 0xFF / 255)
    }
}

/// Change vs. the previous reading, colored conservatively: green only when
/// the value moved from outside the type's healthy range measurably closer
/// to (or into) it. Types with no defined healthy range — weight chief among
/// them, since "lower" isn't inherently better or worse — and any reading
/// that was already inside its range stay neutral gray rather than guessing
/// at a value judgment `AnalysisEngine` doesn't make either.
private struct VitalDelta {
    let symbol: String
    let magnitude: String
    let color: Color
    let directionWord: String
}

private func vitalDelta(for card: VitalCardSummary) -> VitalDelta? {
    guard let previous = card.previous else { return nil }
    let latestDisplay = Units.display(card.latest.value, for: card.type)
    let previousDisplay = Units.display(previous.value, for: card.type)
    let diff = latestDisplay - previousDisplay

    let symbol: String
    let directionWord: String
    if diff > 0.0005 {
        symbol = "\u{2191}"
        directionWord = "up"
    } else if diff < -0.0005 {
        symbol = "\u{2193}"
        directionWord = "down"
    } else {
        symbol = "\u{2192}"
        directionWord = "unchanged"
    }

    return VitalDelta(
        symbol: symbol,
        magnitude: abs(diff).compactFormatted,
        color: deltaColor(type: card.type, previous: previous.value, latest: card.latest.value),
        directionWord: directionWord
    )
}

private func deltaColor(type: VitalType, previous: Double, latest: Double) -> Color {
    guard let range = type.healthyRange else { return .secondary }

    func distanceOutsideRange(_ value: Double) -> Double {
        if value < range.lowerBound { return range.lowerBound - value }
        if value > range.upperBound { return value - range.upperBound }
        return 0
    }

    let previousDistance = distanceOutsideRange(previous)
    let latestDistance = distanceOutsideRange(latest)
    guard previousDistance > 1e-9, latestDistance < previousDistance - 1e-9 else { return .secondary }
    return .green
}

/// One metric card in the Vitals grid: uppercase tinted label, delta vs. the
/// previous reading, big value + unit, a 6-point sparkline, and a relative
/// "when" caption. Tapping the card (via the enclosing `NavigationLink`)
/// drills into `VitalTypeDetailView` for that type's full history.
private struct VitalMetricCard: View {
    let card: VitalCardSummary

    private var tint: Color { vitalTint(for: card.type) }
    private var delta: VitalDelta? { vitalDelta(for: card) }

    private var valueText: String {
        if card.type == .bloodPressure, let secondary = card.latest.secondaryValue {
            return "\(Int(card.latest.value.rounded()))/\(Int(secondary.rounded()))"
        }
        return Units.display(card.latest.value, for: card.type).compactFormatted
    }

    private var unitText: String {
        card.type == .bloodPressure ? card.type.unit : Units.label(for: card.type)
    }

    private var whenText: String {
        "Updated \(card.latest.date.formatted(.relative(presentation: .named)))"
    }

    private var accessibilityText: String {
        var parts = ["\(card.type.displayName), \(valueText) \(unitText)"]
        if let delta {
            parts.append("\(delta.directionWord) \(delta.magnitude) \(unitText) from previous reading")
        }
        parts.append(whenText)
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(card.type.displayName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let delta {
                    Text("\(delta.symbol) \(delta.magnitude)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(delta.color)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unitText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            sparkline
                .frame(height: 26)
            Text(whenText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Decorative recent-history sparkline — hidden from accessibility since
    /// the card's combined label already conveys value, delta, and date.
    @ViewBuilder
    private var sparkline: some View {
        if card.sparklinePoints.count >= 2 {
            Chart(card.sparklinePoints) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: card.type))
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .foregroundStyle(tint)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .accessibilityHidden(true)
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }
}

// MARK: - Per-type history (drill-down)

/// Full history for one vital type: the trend chart and every logged
/// reading with delete, reached by tapping a card in the `VitalsView` grid.
/// This is the pre-redesign `VitalsView` body, scoped to a single `type`
/// instead of driven by a picker, so no existing capability (chart, history,
/// delete, add) is lost by the grid becoming the top-level browse screen.
private struct VitalTypeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allVitals: [VitalSample]

    let type: VitalType

    @State private var showingAdd = false

    /// Narrows the fetch itself to `type` via a predicate on the raw stored
    /// string — `VitalSample.type` is a computed property over `typeRaw`,
    /// and `#Predicate` can only capture plain captured values (not a
    /// computed expression), so `raw` is captured outside the predicate
    /// closure. Replaces a `@Query` over every vital sample that was
    /// re-filtered by `type` on every access (count check, `ForEach`, and
    /// the chart's own sort — three full scans of the whole vitals table per
    /// body pass).
    init(type: VitalType) {
        self.type = type
        let raw = type.rawValue
        _allVitals = Query(
            filter: #Predicate<VitalSample> { $0.typeRaw == raw },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    var body: some View {
        // Body-local: the query is already narrowed to `type`, so this is a
        // cheap alias, not a re-filter — threaded into `chart`/`deleteSamples`
        // instead of each reaching back into `allVitals` separately.
        let samples = allVitals
        List {
            if samples.count >= 2 {
                Section {
                    chart(samples: samples)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            Section("History") {
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
                .onDelete { offsets in deleteSamples(samples, at: offsets) }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
        .ambientScreen()
        .navigationTitle(type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add \(type.displayName.lowercased())")
        }
        .sheet(isPresented: $showingAdd) {
            AddVitalSheet(initialType: type)
        }
    }

    private func chart(samples: [VitalSample]) -> some View {
        let ascending = samples.sorted { $0.date < $1.date }
        return Chart {
            if let healthyRange = type.healthyRange {
                let range = Units.displayRange(healthyRange, for: type)
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(.green.opacity(0.08))
            }
            ForEach(ascending) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: type)),
                    series: .value("Series", "primary")
                )
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: type))
                )
            }
            if type == .bloodPressure {
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
        .chartYAxisLabel(Units.label(for: type))
        .accessibilityLabel("\(type.displayName) trend chart")
    }

    private func deleteSamples(_ samples: [VitalSample], at offsets: IndexSet) {
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
