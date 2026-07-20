import SwiftUI
import SwiftData
import Charts
import UIKit

struct VitalsView: View {
    @Query(sort: \VitalSample.date, order: .reverse) private var vitals: [VitalSample]
    @Query private var profiles: [HealthProfile]

    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAdd = false
    @State private var cards: [VitalCardSummary] = []
    /// False until the first `.task(id:)` pass has populated `cards`. Gates
    /// the empty state so a brief, genuinely-empty `cards` array on first
    /// appearance (before the cache is built) renders a blank screen instead
    /// of flashing "No Vitals Logged" for a screen that actually has data.
    @State private var hasLoaded = false
    /// The vital type the add sheet opens to. Defaults to `initialType`, but
    /// the blood-pressure hero's own "Log blood pressure" button overrides it
    /// to `.bloodPressure` regardless of what this view was constructed with.
    @State private var sheetType: VitalType

    let initialType: VitalType

    init(initialType: VitalType = .weight) {
        self.initialType = initialType
        _sheetType = State(initialValue: initialType)
    }

    private var bpCard: VitalCardSummary? {
        cards.first { $0.type == .bloodPressure }
    }

    private var otherCards: [VitalCardSummary] {
        cards.filter { $0.type != .bloodPressure }
    }

    /// BMI computed from the latest logged weight and the profile's stored
    /// height — a pure, on-the-fly derivation (nothing new is stored) using
    /// `AnalysisEngine.bmi`/`bmiCategory`, the same functions the health
    /// review already relies on.
    private var bmiSummary: (value: Double, category: (name: String, severity: Severity))? {
        guard let heightCm = profiles.first?.heightCm, heightCm > 0,
              let weightKg = vitals.first(where: { $0.type == .weight })?.value,
              let bmi = AnalysisEngine.bmi(weightKg: weightKg, heightCm: heightCm) else { return nil }
        return (bmi, AnalysisEngine.bmiCategory(bmi))
    }

    var body: some View {
        Group {
            if hasLoaded && cards.isEmpty {
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
                    VStack(alignment: .leading, spacing: 24) {
                        if let bpCard {
                            bloodPressureHero(bpCard)
                        }

                        if !otherCards.isEmpty || bmiSummary != nil {
                            VStack(alignment: .leading, spacing: 0) {
                                MicroLabel("Other Vitals")
                                    .padding(.bottom, 8)
                                ForEach(otherCards) { card in
                                    NavigationLink {
                                        VitalTypeDetailView(type: card.type)
                                    } label: {
                                        VitalLedgerRow(card: card)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if let bmiSummary {
                                    bmiRow(bmiSummary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Vitals")
        .toolbar {
            Button {
                sheetType = initialType
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add vital")
        }
        .sheet(isPresented: $showingAdd) {
            AddVitalSheet(initialType: sheetType)
        }
        .task(id: vitals.count) {
            cards = Self.buildCards(from: vitals)
            hasLoaded = true
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

    // MARK: - Blood pressure hero

    /// Featured blood-pressure block: the latest reading, its ACC/AHA
    /// category tag, a zone `RangeBar` positioned by systolic pressure, and
    /// the one prominent filled CTA on this screen ("Log blood pressure").
    @ViewBuilder
    private func bloodPressureHero(_ card: VitalCardSummary) -> some View {
        let systolic = card.latest.value
        let diastolic = card.latest.secondaryValue ?? systolic
        let category = AnalysisEngine.bloodPressureCategory(systolic: systolic, diastolic: diastolic)
        let bar = bpZones(systolic: systolic)
        let whenText = card.latest.date.formatted(.relative(presentation: .named))

        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(verbatim: String(format: String(localized: "%@ · %@"), VitalType.bloodPressure.displayName, whenText))

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                HStack(alignment: .top, spacing: 0) {
                    Text("\(Int(systolic.rounded()))")
                    Text("/\(Int(diastolic.rounded()))")
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Editorial.ink(colorScheme))

                EditorialTag(verbatim: category.displayName, kind: tagKind(for: category))
            }

            VStack(alignment: .leading, spacing: 6) {
                RangeBar(
                    zones: bar.zones,
                    marker: bar.marker,
                    accessibilityLabel: Text(
                        "\(VitalType.bloodPressure.displayName) \(Int(systolic.rounded()))/\(Int(diastolic.rounded())) \(VitalType.bloodPressure.unit), \(category.displayName)"
                    )
                )
                HStack {
                    Text("normal")
                    Spacer()
                    Text("elevated")
                    Spacer()
                    Text("stage 1")
                    Spacer()
                    Text("stage 2")
                }
                .font(.system(size: 10))
                .foregroundStyle(Editorial.muted(colorScheme))
            }

            Text("ACC/AHA categories")
                .font(.system(size: 11))
                .foregroundStyle(Editorial.muted(colorScheme))

            Button {
                sheetType = .bloodPressure
                showingAdd = true
            } label: {
                Text("Log blood pressure")
            }
            .buttonStyle(GlassProminentButtonStyle())
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    /// Zone widths derived from the real ACC/AHA systolic thresholds (120,
    /// 130, 140 mmHg) over a 90–180 mmHg axis, rather than eyeballed
    /// percentages — keeps the bar's proportions medically meaningful. Only
    /// three `RangeZoneKind` colors exist, so elevated/stage 1/stage 2 all
    /// render as the same "out of range" tone; the marker position and the
    /// axis captions below still make the finer distinction clear.
    private func bpZones(systolic: Double) -> (zones: [(fraction: CGFloat, kind: RangeZoneKind)], marker: CGFloat) {
        let axisMin = 90.0
        let axisMax = 180.0
        let span = axisMax - axisMin
        func fraction(_ value: Double) -> CGFloat {
            CGFloat(min(1, max(0, (value - axisMin) / span)))
        }
        let normalEnd = fraction(120)
        let elevatedEnd = fraction(130)
        let stage1End = fraction(140)
        let zones: [(fraction: CGFloat, kind: RangeZoneKind)] = [
            (normalEnd, .inRange),
            (elevatedEnd - normalEnd, .out),
            (stage1End - elevatedEnd, .out),
            (1 - stage1End, .out),
        ]
        return (zones, fraction(systolic))
    }

    /// Matches the token spec: normal is the good tag, elevated/stage 1 read
    /// as the cautionary amber tag, and stage 2/crisis read as the urgent
    /// red tag.
    private func tagKind(for category: BloodPressureCategory) -> TagKind {
        switch category {
        case .normal: .good
        case .elevated, .stage1: .warn
        case .stage2, .crisis: .bad
        }
    }

    // MARK: - BMI row

    private func tagKind(for severity: Severity) -> TagKind {
        switch severity {
        case .info: .good
        case .attention: .warn
        case .critical: .bad
        }
    }

    private func bmiRow(_ summary: (value: Double, category: (name: String, severity: Severity))) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("BMI")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                HStack(spacing: 8) {
                    Text(summary.value.compactFormatted)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    EditorialTag(verbatim: summary.category.name, kind: tagKind(for: summary.category.severity))
                }
            }
            RangeBar(
                lower: 18.5,
                upper: 25,
                min: 15,
                max: 40,
                value: summary.value,
                accessibilityLabel: Text("\(String(localized: "BMI")) \(summary.value.compactFormatted), \(summary.category.name)")
            )
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Vital summary (pure model)

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

/// Change vs. the previous reading, colored conservatively: the good tag
/// color only when the value moved from outside the type's healthy range
/// measurably closer to (or into) it. Types with no defined healthy range —
/// weight chief among them, since "lower" isn't inherently better or worse —
/// and any reading that was already inside its range stay muted rather than
/// guessing at a value judgment `AnalysisEngine` doesn't make either.
private struct VitalDelta {
    let symbol: String
    let magnitude: String
    let color: Color
    let directionWord: String
}

private func vitalDelta(for card: VitalCardSummary, colorScheme: ColorScheme) -> VitalDelta? {
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
        color: deltaColor(type: card.type, previous: previous.value, latest: card.latest.value, colorScheme: colorScheme),
        directionWord: directionWord
    )
}

private func deltaColor(type: VitalType, previous: Double, latest: Double, colorScheme: ColorScheme) -> Color {
    guard let range = type.healthyRange else { return Editorial.muted(colorScheme) }

    func distanceOutsideRange(_ value: Double) -> Double {
        if value < range.lowerBound { return range.lowerBound - value }
        if value > range.upperBound { return value - range.upperBound }
        return 0
    }

    let previousDistance = distanceOutsideRange(previous)
    let latestDistance = distanceOutsideRange(latest)
    guard previousDistance > 1e-9, latestDistance < previousDistance - 1e-9 else { return Editorial.muted(colorScheme) }
    return Editorial.tagGood(colorScheme)
}

// MARK: - Vital ledger row

/// One flat ledger row in the "Other Vitals" list: type name, a muted
/// caption combining the delta since the previous reading with a relative
/// "updated" time, a small ink sparkline, and the value + unit. Tapping the
/// row (via the enclosing `NavigationLink`) drills into
/// `VitalTypeDetailView` for that type's full history.
private struct VitalLedgerRow: View {
    let card: VitalCardSummary

    @Environment(\.colorScheme) private var colorScheme

    private var delta: VitalDelta? { vitalDelta(for: card, colorScheme: colorScheme) }

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

    private var secondaryCaption: String {
        guard let delta else { return whenText }
        return "\(delta.symbol) \(delta.magnitude) \(unitText) · \(whenText)"
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.type.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .lineLimit(1)
                Text(secondaryCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(delta?.color ?? Editorial.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            sparkline
                .frame(width: 60, height: 24)
            VStack(alignment: .trailing, spacing: 2) {
                Text(valueText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(unitText)
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Decorative recent-history sparkline — hidden from accessibility since
    /// the row's own accessibility label already conveys value, delta, and
    /// date.
    @ViewBuilder
    private var sparkline: some View {
        if card.sparklinePoints.count >= 2 {
            Chart(card.sparklinePoints) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: card.type))
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            .foregroundStyle(Editorial.ink(colorScheme))
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
/// reading with delete, reached by tapping a row in the `VitalsView` ledger.
private struct VitalTypeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(samples) { sample in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 14))
                                .foregroundStyle(Editorial.ink(colorScheme))
                            if !sample.note.isEmpty {
                                Text(sample.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Editorial.muted(colorScheme))
                            }
                        }
                        Spacer()
                        Text(sample.formattedValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                    }
                    .ledgerRow()
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in deleteSamples(samples, at: offsets) }
            } header: {
                MicroLabel("History")
            }
            .listRowBackground(Color.clear)
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
                .foregroundStyle(Editorial.zoneIn(colorScheme).opacity(0.5))
            }
            ForEach(ascending) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: type)),
                    series: .value("Series", "primary")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Editorial.ink(colorScheme))
                PointMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", Units.display(sample.value, for: type))
                )
                .foregroundStyle(Editorial.ink(colorScheme))
            }
            if type == .bloodPressure {
                ForEach(ascending.filter { $0.secondaryValue != nil }) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Diastolic", sample.secondaryValue ?? 0),
                        series: .value("Series", "secondary")
                    )
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Editorial.hairline(colorScheme))
                AxisTick().foregroundStyle(Editorial.muted(colorScheme))
                AxisValueLabel().foregroundStyle(Editorial.muted(colorScheme))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Editorial.hairline(colorScheme))
                AxisTick().foregroundStyle(Editorial.muted(colorScheme))
                AxisValueLabel().foregroundStyle(Editorial.muted(colorScheme))
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
    /// Guards `save()` against a double tap firing two inserts before the
    /// sheet has dismissed — checked and set at the top of `save()`, and
    /// mirrored onto the Save button's `disabled` state.
    @State private var isSaving = false

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
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func save() {
        guard !isSaving else { return }
        guard let value = parsedValue else { return }
        isSaving = true
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

/// Horizontally scrolling icon chip used to pick the vital type without a
/// system Picker wheel.
private struct VitalTypeChip: View {
    let type: VitalType
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .background(
                        Circle().fill(isSelected ? AnyShapeStyle(Glass.accentGradient) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .overlay(Circle().strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1))
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
