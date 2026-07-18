import SwiftUI
import SwiftData
import Charts

struct MetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct MetricSeries: Identifiable {
    let id: String
    let name: String
    let unit: String
    let range: ClosedRange<Double>?
    let points: [MetricPoint]
}

enum TrendTimeRange: String, CaseIterable, Identifiable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var months: Int? {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .year: 12
        case .all: nil
        }
    }
}

struct TrendsView: View {
    @Query private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var profiles: [HealthProfile]

    @State private var selectedSeriesID: String?
    @State private var timeRange: TrendTimeRange = .all
    @State private var selectedDate: Date?

    /// Cached instead of recomputed per render — `buildSeries` groups every
    /// lab result across every report plus 8x filter+sorts the vitals, and
    /// was previously an uncached computed property read 3-6x per body pass
    /// (and the body reruns continuously while `.chartXSelection` mutates
    /// `selectedDate` during a chart-scrub drag). Rebuilt only when
    /// `seriesSignature` changes.
    @State private var allSeries: [MetricSeries] = []
    /// Guards against flashing the "Not Enough Data" empty state for the one
    /// frame before the initial `.task` build completes.
    @State private var hasBuiltSeries = false

    /// Covers everything `buildSeries` reads: report/vital *counts* alone
    /// would miss a lab result added to an already-counted report, so the
    /// flattened lab-result count stands in for its contents too.
    private var seriesSignature: String {
        let labResultCount = reports.reduce(0) { $0 + $1.labResults.count }
        return "\(reports.count)-\(labResultCount)-\(vitals.count)-\(profiles.first?.sex.rawValue ?? "")"
    }

    /// Pure builder for `allSeries` — see the `@State` declaration above for
    /// why this must not run as a plain computed property.
    private static func buildSeries(reports: [MedicalReport], vitals: [VitalSample], sex: BiologicalSex?) -> [MetricSeries] {
        var series: [MetricSeries] = []

        // Lab test series (grouped across all reports).
        let grouped = Dictionary(grouping: reports.flatMap { $0.labResults }) { $0.seriesKey }
        for (key, results) in grouped.sorted(by: { $0.key < $1.key }) {
            let sorted = results.sorted { $0.date < $1.date }
            guard sorted.count >= 2, let latest = sorted.last else { continue }
            series.append(MetricSeries(
                id: key,
                name: latest.displayName,
                unit: latest.unit,
                range: latest.referenceRange(for: sex),
                points: sorted.map { MetricPoint(date: $0.date, value: $0.value) }
            ))
        }

        // Vital series.
        for type in VitalType.allCases {
            let samples = vitals.filter { $0.type == type }.sorted { $0.date < $1.date }
            guard samples.count >= 2 else { continue }
            if type == .bloodPressure {
                series.append(MetricSeries(
                    id: "vital:\(type.rawValue):systolic",
                    name: "Systolic Pressure",
                    unit: type.unit,
                    range: 90...120,
                    points: samples.map { MetricPoint(date: $0.date, value: $0.value) }
                ))
                let diastolic = samples.compactMap { sample -> MetricPoint? in
                    guard let value = sample.secondaryValue else { return nil }
                    return MetricPoint(date: sample.date, value: value)
                }
                if diastolic.count >= 2 {
                    series.append(MetricSeries(
                        id: "vital:\(type.rawValue):diastolic",
                        name: "Diastolic Pressure",
                        unit: type.unit,
                        range: 60...80,
                        points: diastolic
                    ))
                }
            } else {
                series.append(MetricSeries(
                    id: "vital:\(type.rawValue)",
                    name: type.displayName,
                    unit: Units.label(for: type),
                    range: type.healthyRange.map { Units.displayRange($0, for: type) },
                    points: samples.map { MetricPoint(date: $0.date, value: Units.display($0.value, for: type)) }
                ))
            }
        }
        return series
    }

    private var selectedSeries: MetricSeries? {
        allSeries.first { $0.id == selectedSeriesID } ?? allSeries.first
    }

    private var timeRangeDescription: String {
        switch timeRange {
        case .threeMonths: "last 3 months"
        case .sixMonths: "last 6 months"
        case .year: "last year"
        case .all: "all time"
        }
    }

    /// When `series` is one half of a blood-pressure reading, returns the
    /// matching systolic/diastolic pair from `allSeries` so both can be
    /// charted together. Returns `nil` for every other metric, and for
    /// blood-pressure vitals that never recorded a diastolic value.
    private func bloodPressurePair(for series: MetricSeries) -> (systolic: MetricSeries, diastolic: MetricSeries)? {
        let prefix = "vital:\(VitalType.bloodPressure.rawValue):"
        guard series.id.hasPrefix(prefix),
              let systolic = allSeries.first(where: { $0.id == "\(prefix)systolic" }),
              let diastolic = allSeries.first(where: { $0.id == "\(prefix)diastolic" }) else {
            return nil
        }
        return (systolic, diastolic)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasBuiltSeries {
                    // First-build gap before `.task` below runs — avoids
                    // flashing "Not Enough Data" while `allSeries` is still
                    // its initial empty value.
                    Color.clear
                } else if allSeries.isEmpty {
                    ContentUnavailableView(
                        "Not Enough Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Add at least two entries of the same lab test or vital to see its trend over time.")
                    )
                } else if let series = selectedSeries {
                    trendsList(for: series)
                }
            }
            .ambientScreen()
            .navigationTitle("Trends")
            .toolbar {
                NavigationLink {
                    HealthTimelineView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("View health timeline")
            }
        }
        .task(id: seriesSignature) {
            allSeries = Self.buildSeries(reports: reports, vitals: vitals, sex: profiles.first?.sex)
            hasBuiltSeries = true
        }
    }

    private func trendsList(for series: MetricSeries) -> some View {
        let points = visiblePoints(for: series)
        return List {
            Section {
                metricChipsRow(selectedID: series.id)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            Section {
                rangeChipsRow
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            Section {
                if points.count >= 2 {
                    chart(for: series, points: points)
                        .frame(height: 240)
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                } else {
                    Text("Not enough entries in this time range.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section("Statistics") {
                statsRows(for: series, points: points)
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
    }

    /// Horizontally scrolling metric-selection chips. The active metric
    /// gets the accent-gradient fill with dark ink text — legible against
    /// the bright gradient in either light or dark mode; every other chip is
    /// a plain glass pill, matching the chip rows used elsewhere in the app
    /// (see `HealthTimelineView.chip`, `DocumentsView.categoryChip`).
    private func metricChipsRow(selectedID: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allSeries) { candidate in
                    let isSelected = candidate.id == selectedID
                    Button {
                        selectedSeriesID = candidate.id
                    } label: {
                        Text(candidate.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Self.selectedChipTextColor : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if isSelected {
                                    Capsule().fill(Glass.accentGradient)
                                } else {
                                    Capsule().fill(.ultraThinMaterial)
                                }
                            }
                            .overlay(Capsule().strokeBorder(Glass.bevelStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Segmented range control (3M/6M/1Y/All): the active range gets a
    /// subtle translucent white highlight over the glass track, matching the
    /// prototype's range chips.
    private var rangeChipsRow: some View {
        HStack(spacing: 2) {
            ForEach(TrendTimeRange.allCases) { range in
                let isSelected = range == timeRange
                Button {
                    timeRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Glass.bevelStroke, lineWidth: 1)
        )
    }

    /// Dark ink (`#0B1220`-equivalent) used for text sitting directly on the
    /// accent gradient — always legible regardless of light/dark mode,
    /// matching the prototype's selected-chip treatment.
    private static let selectedChipTextColor = Color(red: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x20 / 255.0)

    private func visiblePoints(for series: MetricSeries) -> [MetricPoint] {
        guard let months = timeRange.months,
              let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: .now) else {
            return series.points
        }
        return series.points.filter { $0.date >= cutoff }
    }

    private func periodAverage(_ points: [MetricPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        let total = points.reduce(0) { $0 + $1.value }
        return total / Double(points.count)
    }

    private func periodMinPoint(_ points: [MetricPoint]) -> MetricPoint? {
        points.min { $0.value < $1.value }
    }

    private func periodMaxPoint(_ points: [MetricPoint]) -> MetricPoint? {
        points.max { $0.value < $1.value }
    }

    /// Y-axis domain padded beyond the visible values (and the healthy-range
    /// band, when present) so nothing sits flush against the chart edges.
    private func yDomain(values: [Double], range: ClosedRange<Double>?) -> ClosedRange<Double> {
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if let range {
            low = min(low, range.lowerBound)
            high = max(high, range.upperBound)
        }
        if low == high {
            low -= 1
            high += 1
        }
        let padding = (high - low) * 0.12
        return (low - padding)...(high + padding)
    }

    @ViewBuilder
    private func chart(for series: MetricSeries, points: [MetricPoint]) -> some View {
        let pair = bloodPressurePair(for: series)
        let systolicPoints = pair.map { visiblePoints(for: $0.systolic) } ?? []
        let diastolicPoints = pair.map { visiblePoints(for: $0.diastolic) } ?? []
        let domainValues = pair == nil ? points.map(\.value) : (systolicPoints + diastolicPoints).map(\.value)
        let average = periodAverage(points)
        let minPoint = periodMinPoint(points)
        let maxPoint = periodMaxPoint(points)
        let maxDiffersFromMin = maxPoint?.id != minPoint?.id

        Chart {
            if let range = series.range {
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(.green.opacity(0.1))
            }

            if let pair {
                // Blood pressure: systolic and diastolic charted as two
                // color-coded series with an automatic legend.
                ForEach(systolicPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(pair.systolic.name, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Reading", pair.systolic.name))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(pair.systolic.name, point.value)
                    )
                    .foregroundStyle(by: .value("Reading", pair.systolic.name))
                }
                ForEach(diastolicPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(pair.diastolic.name, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Reading", pair.diastolic.name))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(pair.diastolic.name, point.value)
                    )
                    .foregroundStyle(by: .value("Reading", pair.diastolic.name))
                }
            } else {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value(series.name, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.30), Color.teal.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(series.name, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Glass.accentGradient)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(series.name, point.value)
                    )
                    .foregroundStyle(Glass.accentGradient)
                }
            }

            // The four annotations below are staggered across distinct
            // corners (average top, max top-trailing, selection top-leading,
            // min bottom) so their captions can't stack on top of each other
            // when several are visible at once. Each also clamps to the plot
            // area (`y: .fit(to: .plot)` instead of `.disabled`) so Charts
            // keeps them inside the chart instead of letting them overflow.
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.orange.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                    ) {
                        Text("avg \(average.compactFormatted)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
            }

            if let minPoint {
                PointMark(
                    x: .value("Date", minPoint.date),
                    y: .value(series.name, minPoint.value)
                )
                .symbolSize(90)
                .foregroundStyle(.purple)
                .annotation(
                    position: .bottom,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                ) {
                    Text(minPoint.value.compactFormatted)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
            if let maxPoint, maxDiffersFromMin {
                PointMark(
                    x: .value("Date", maxPoint.date),
                    y: .value(series.name, maxPoint.value)
                )
                .symbolSize(90)
                .foregroundStyle(.purple)
                .annotation(
                    position: .topTrailing,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                ) {
                    Text(maxPoint.value.compactFormatted)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }

            if let selectedDate, let selected = nearestPoint(to: selectedDate, in: points) {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(
                        position: .topLeading,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                    ) {
                        VStack(spacing: 2) {
                            Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(selected.value.compactFormatted) \(series.unit)")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                        )
                    }
            }
        }
        .chartLegend(pair == nil ? .hidden : .visible)
        .chartXSelection(value: $selectedDate)
        .chartYAxisLabel(series.unit)
        .chartYScale(domain: yDomain(values: domainValues, range: series.range))
        .accessibilityLabel("\(series.name) trend, \(timeRangeDescription)")
    }

    private func nearestPoint(to date: Date, in points: [MetricPoint]) -> MetricPoint? {
        points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    @ViewBuilder
    private func statsRows(for series: MetricSeries, points: [MetricPoint]) -> some View {
        let values = points.map(\.value)
        if let latest = points.last, let minValue = values.min(), let maxValue = values.max() {
            LabeledContent("Latest", value: "\(latest.value.compactFormatted) \(series.unit)")
            LabeledContent("Lowest", value: "\(minValue.compactFormatted) \(series.unit)")
            LabeledContent("Highest", value: "\(maxValue.compactFormatted) \(series.unit)")
            LabeledContent("Entries", value: "\(points.count)")
            if let range = series.range {
                LabeledContent(
                    "Typical Range",
                    value: "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(series.unit)"
                )
            }
            if let (direction, percentChange) = AnalysisEngine.trend(
                points: points.map { (date: $0.date, value: $0.value) },
                range: series.range
            ) {
                LabeledContent("Trend") {
                    HStack(spacing: 6) {
                        Image(systemName: direction.systemImage)
                            .foregroundStyle(direction.color)
                            .accessibilityHidden(true)
                        Text("\(direction.displayName) (\(String(format: "%+.0f%%", percentChange)))")
                            .foregroundStyle(direction.color)
                    }
                }
            }
        }
    }
}
