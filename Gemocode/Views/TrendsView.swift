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

    @Environment(\.colorScheme) private var colorScheme

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
                    name: String(localized: "Systolic Pressure"),
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
                        name: String(localized: "Diastolic Pressure"),
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
        case .threeMonths: String(localized: "last 3 months")
        case .sixMonths: String(localized: "last 6 months")
        case .year: String(localized: "last year")
        case .all: String(localized: "all time")
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
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(allSeries) { series in
                                ledgerRow(series)
                            }

                            if let series = selectedSeries {
                                detailSection(for: series)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                    }
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

    // MARK: - Ledger

    /// One flat ledger row per metric: a small filled/hollow dot marking
    /// whether this is the metric currently expanded below, the name plus a
    /// muted trend caption ("Rising · 5.6 → 5.9"), a small ink sparkline of
    /// its most recent points, and a status tag. Tapping selects the metric,
    /// swapping the interactive chart + stats shown underneath the ledger.
    private func ledgerRow(_ series: MetricSeries) -> some View {
        let isSelected = series.id == (selectedSeries?.id ?? "")
        return Button {
            selectedSeriesID = series.id
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Editorial.ink(colorScheme) : Color.clear)
                    .overlay(
                        Circle().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: isSelected ? 0 : 1)
                    )
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(series.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                        .lineLimit(1)
                    if let trend = trendCaption(for: series) {
                        HStack(spacing: 4) {
                            Image(systemName: trend.symbol)
                            Text(trend.text)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                rowSparkline(series)

                tagView(for: series)
            }
        }
        .buttonStyle(.plain)
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// Small ink sparkline (last 12 points) with an accent dot marking the
    /// most recent reading — matches the mini-chart used in the row grammar
    /// throughout the editorial system (see `BiomarkerRow`).
    @ViewBuilder
    private func rowSparkline(_ series: MetricSeries) -> some View {
        let recent = Array(series.points.suffix(12))
        if recent.count >= 2 {
            Chart {
                ForEach(Array(recent.enumerated()), id: \.offset) { entry in
                    LineMark(
                        x: .value("Index", entry.offset),
                        y: .value("Value", entry.element.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
                .foregroundStyle(Editorial.ink(colorScheme))

                if let lastIndex = recent.indices.last {
                    PointMark(
                        x: .value("Index", lastIndex),
                        y: .value("Value", recent[lastIndex].value)
                    )
                    .symbolSize(24)
                    .foregroundStyle(Editorial.accent(colorScheme))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .accessibilityHidden(true)
            .frame(width: 90, height: 30)
        } else {
            Color.clear.frame(width: 90, height: 30).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func tagView(for series: MetricSeries) -> some View {
        if let latest = series.points.last {
            let status = AnalysisEngine.status(value: latest.value, range: series.range)
            EditorialTag(verbatim: status.label, kind: tagKind(for: status))
        }
    }

    /// Maps a lab/vital status to the editorial tag palette. Matches the
    /// token spec exactly: "High" reads as the cautionary amber tag, "Low"
    /// (and any critical flag) reads as the more urgent red tag.
    private func tagKind(for status: LabStatus) -> TagKind {
        switch status {
        case .normal: .good
        case .high: .warn
        case .low, .criticalLow, .criticalHigh: .bad
        case .unknown: .warn
        }
    }

    /// Trend caption built from the metric's full history (not the visible
    /// time-range window), matching the ledger grammar's "↗ rising · 5.6 →
    /// 5.9" summary line. `nil` when there aren't enough points to classify
    /// a trend.
    private func trendCaption(for series: MetricSeries) -> (symbol: String, text: String)? {
        guard series.points.count >= 3,
              let first = series.points.first,
              let last = series.points.last,
              let (direction, _) = AnalysisEngine.trend(
                  points: series.points.map { (date: $0.date, value: $0.value) },
                  range: series.range
              ) else { return nil }
        let text = "\(direction.displayName) · \(first.value.compactFormatted) → \(last.value.compactFormatted)"
        return (direction.systemImage, text)
    }

    // MARK: - Detail (range picker + chart + stats)

    @ViewBuilder
    private func detailSection(for series: MetricSeries) -> some View {
        let points = visiblePoints(for: series)
        VStack(alignment: .leading, spacing: 14) {
            rangePicker
                .padding(.top, 18)

            if points.count >= 2 {
                chart(for: series, points: points)
                    .frame(height: 240)
                    .padding(.vertical, 4)
            } else {
                Text("Not enough entries in this time range.")
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }

            MicroLabel("Statistics")
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 0) {
                statsRows(for: series, points: points)
            }
        }
    }

    /// Quiet text segmented control for the 3M/6M/1Y/All window — no pill
    /// backgrounds, just weight/color contrast between the active and
    /// inactive labels.
    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(TrendTimeRange.allCases) { range in
                let isSelected = range == timeRange
                Button {
                    timeRange = range
                } label: {
                    // Deliberately verbatim: these are short abbreviations
                    // ("3M", "1Y", "All") rather than translated phrases —
                    // matches their pre-redesign display, which passed the
                    // raw `rawValue` straight to `Text`.
                    Text(verbatim: range.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Editorial.ink(colorScheme) : Editorial.muted(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

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
        // Empty when `pair` is nil — the single-series branch below styles
        // its line directly rather than through `foregroundStyle(by:)`, so
        // this scale is only consulted for the dual-series blood-pressure
        // case, mapping systolic to ink and diastolic to muted.
        let scaleDomain: [String] = pair.map { [$0.systolic.name, $0.diastolic.name] } ?? []
        let scaleRange: [Color] = pair == nil ? [] : [Editorial.ink(colorScheme), Editorial.muted(colorScheme)]

        Chart {
            if let range = series.range {
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(Editorial.zoneIn(colorScheme).opacity(0.5))
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
                            colors: [Editorial.ink(colorScheme).opacity(0.14), Editorial.ink(colorScheme).opacity(0)],
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
                    .foregroundStyle(Editorial.ink(colorScheme))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(series.name, point.value)
                    )
                    .foregroundStyle(Editorial.ink(colorScheme))
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
                    .foregroundStyle(Editorial.muted(colorScheme).opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                    ) {
                        Text("avg \(average.compactFormatted)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Editorial.muted(colorScheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Editorial.insetCard(colorScheme), in: Capsule())
                    }
            }

            if let minPoint {
                PointMark(
                    x: .value("Date", minPoint.date),
                    y: .value(series.name, minPoint.value)
                )
                .symbolSize(90)
                .foregroundStyle(Editorial.accent(colorScheme))
                .annotation(
                    position: .bottom,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                ) {
                    Text(minPoint.value.compactFormatted)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Editorial.accent(colorScheme))
                }
            }
            if let maxPoint, maxDiffersFromMin {
                PointMark(
                    x: .value("Date", maxPoint.date),
                    y: .value(series.name, maxPoint.value)
                )
                .symbolSize(90)
                .foregroundStyle(Editorial.accent(colorScheme))
                .annotation(
                    position: .topTrailing,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                ) {
                    Text(maxPoint.value.compactFormatted)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Editorial.accent(colorScheme))
                }
            }

            if let selectedDate, let selected = nearestPoint(to: selectedDate, in: points) {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Editorial.muted(colorScheme).opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(
                        position: .topLeading,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                    ) {
                        VStack(spacing: 2) {
                            Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(Editorial.muted(colorScheme))
                            Text("\(selected.value.compactFormatted) \(series.unit)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Editorial.ink(colorScheme))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1)
                        )
                    }
            }
        }
        .chartForegroundStyleScale(domain: scaleDomain, range: scaleRange)
        .chartLegend(pair == nil ? .hidden : .visible)
        .chartXSelection(value: $selectedDate)
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
            statRow("Latest", value: "\(latest.value.compactFormatted) \(series.unit)")
            statRow("Lowest", value: "\(minValue.compactFormatted) \(series.unit)")
            statRow("Highest", value: "\(maxValue.compactFormatted) \(series.unit)")
            statRow("Entries", value: "\(points.count)")
            if let range = series.range {
                statRow(
                    "Typical Range",
                    value: "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(series.unit)"
                )
            }
            if let (direction, percentChange) = AnalysisEngine.trend(
                points: points.map { (date: $0.date, value: $0.value) },
                range: series.range
            ) {
                HStack {
                    Text("Trend")
                        .font(.system(size: 15))
                        .foregroundStyle(Editorial.muted(colorScheme))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: direction.systemImage)
                            .accessibilityHidden(true)
                        Text("\(direction.displayName) (\(String(format: "%+.0f%%", percentChange)))")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(trendColor(direction))
                }
                .ledgerRow()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func statRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Editorial.muted(colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Editorial.ink(colorScheme))
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    private func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .improving: Editorial.tagGood(colorScheme)
        case .worsening: Editorial.tagBad(colorScheme)
        case .stable, .rising, .falling: Editorial.muted(colorScheme)
        }
    }
}
