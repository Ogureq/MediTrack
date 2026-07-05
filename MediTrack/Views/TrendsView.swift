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

    private var allSeries: [MetricSeries] {
        var series: [MetricSeries] = []
        let sex = profiles.first?.sex

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
                    unit: type.unit,
                    range: type.healthyRange,
                    points: samples.map { MetricPoint(date: $0.date, value: $0.value) }
                ))
            }
        }
        return series
    }

    private var selectedSeries: MetricSeries? {
        allSeries.first { $0.id == selectedSeriesID } ?? allSeries.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if allSeries.isEmpty {
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
        }
    }

    private func trendsList(for series: MetricSeries) -> some View {
        let points = visiblePoints(for: series)
        return List {
            Section {
                Picker("Metric", selection: Binding(
                    get: { series.id },
                    set: { selectedSeriesID = $0 }
                )) {
                    ForEach(allSeries) { candidate in
                        Text(candidate.name).tag(candidate.id)
                    }
                }
                Picker("Range", selection: $timeRange) {
                    ForEach(TrendTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
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

    private func visiblePoints(for series: MetricSeries) -> [MetricPoint] {
        guard let months = timeRange.months,
              let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: .now) else {
            return series.points
        }
        return series.points.filter { $0.date >= cutoff }
    }

    @ViewBuilder
    private func chart(for series: MetricSeries, points: [MetricPoint]) -> some View {
        Chart {
            if let range = series.range {
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(.green.opacity(0.1))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(series.name, point.value)
                )
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(series.name, point.value)
                )
            }
            if let selectedDate, let selected = nearestPoint(to: selectedDate, in: points) {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
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
        .chartXSelection(value: $selectedDate)
        .chartYAxisLabel(series.unit)
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
                        Text("\(direction.displayName) (\(String(format: "%+.0f%%", percentChange)))")
                            .foregroundStyle(direction.color)
                    }
                }
            }
        }
    }
}
