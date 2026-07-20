import SwiftUI
import SwiftData
import Charts

/// Full history and explanation for one lab test, reachable from the
/// Health Review and from report detail screens.
struct LabDetailView: View {
    let seriesKey: String

    @Query private var reports: [MedicalReport]
    @Query private var profiles: [HealthProfile]

    @Environment(\.colorScheme) private var colorScheme

    /// Cached instead of a plain computed property — flattening every
    /// report's lab results and filtering to this series was previously
    /// redone on every access (~6x per body pass: the empty check, the nav
    /// title, the history-count check, the history chart, the history rows,
    /// and the chart's own `ForEach`). Rebuilt only when `reports.count`
    /// changes, matching `DocumentsView`'s `allItems` cache.
    @State private var results: [LabResult] = []
    /// Guards against flashing "No Results" for the one frame before the
    /// initial `.task` build completes.
    @State private var hasBuiltResults = false

    /// Pure builder for `results` — see the `@State` declaration above.
    private static func buildResults(reports: [MedicalReport], seriesKey: String) -> [LabResult] {
        reports.flatMap(\.labResults)
            .filter { $0.seriesKey == seriesKey }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if !hasBuiltResults {
                Color.clear
            } else if let latest = results.last {
                ScrollView {
                    content(latest: latest)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                }
            } else {
                ContentUnavailableView("No Results", systemImage: "testtube.2")
            }
        }
        .ambientScreen()
        .navigationTitle(results.last?.displayName ?? String(localized: "Lab Test"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reports.count) {
            results = Self.buildResults(reports: reports, seriesKey: seriesKey)
            hasBuiltResults = true
        }
    }

    @ViewBuilder
    private func content(latest: LabResult) -> some View {
        let sex = profiles.first?.sex
        let reference = latest.catalogReference
        let range = latest.referenceRange(for: sex)
        let status = AnalysisEngine.status(
            value: latest.value,
            range: range,
            criticalLow: reference?.criticalLow,
            criticalHigh: reference?.criticalHigh
        )

        VStack(alignment: .leading, spacing: 22) {
            header(latest: latest, status: status)

            if let range {
                VStack(alignment: .leading, spacing: 6) {
                    RangeBar(
                        lower: range.lowerBound,
                        upper: range.upperBound,
                        min: axisBounds(range: range, value: latest.value).min,
                        max: axisBounds(range: range, value: latest.value).max,
                        value: latest.value,
                        accessibilityLabel: Text(
                            "\(latest.displayName) \(latest.value.compactFormatted) \(latest.unit), \(status.label)"
                        )
                    )
                    rangeCaptionRow(range: range)
                }
            }

            if results.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("Trend")
                    historyChart(range: range)
                        .frame(height: 180)
                }
            }

            if let reference {
                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("About This Test")
                    Text(reference.about)
                        .font(.system(size: 14))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    explainerRow(icon: "arrow.down.circle", text: reference.lowMeaning)
                    explainerRow(icon: "arrow.up.circle", text: reference.highMeaning)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                MicroLabel("Details")
                    .padding(.bottom, 6)
                detailsRows(latest: latest, range: range, reference: reference)
            }

            VStack(alignment: .leading, spacing: 0) {
                MicroLabel("History")
                    .padding(.bottom, 6)
                ForEach(results.reversed()) { result in
                    historyRow(result, sex: sex)
                }
            }
        }
    }

    // MARK: - Header

    private func header(latest: LabResult, status: LabStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                HStack(alignment: .top, spacing: 3) {
                    Text(latest.value.compactFormatted)
                        .font(.system(size: 44, weight: .regular))
                    Text(latest.unit)
                        .font(.system(size: 18))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
                .foregroundStyle(Editorial.ink(colorScheme))
                EditorialTag(verbatim: status.label, kind: tagKind(for: status))
                Spacer(minLength: 0)
            }
            Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .accessibilityElement(children: .combine)
    }

    /// Low/normal/high caption row shown directly under the header
    /// `RangeBar`, matching the mockup's "low <4.0 · normal 4.0–5.6 · high
    /// >5.6" legend.
    private func rangeCaptionRow(range: ClosedRange<Double>) -> some View {
        HStack {
            Text(String(format: String(localized: "low <%@"), range.lowerBound.compactFormatted))
            Spacer()
            Text(String(format: String(localized: "normal %@–%@"), range.lowerBound.compactFormatted, range.upperBound.compactFormatted))
            Spacer()
            Text(String(format: String(localized: "high >%@"), range.upperBound.compactFormatted))
        }
        .font(.system(size: 10))
        .foregroundStyle(Editorial.muted(colorScheme))
    }

    /// Extends the reference range with padding on both sides so the
    /// `RangeBar` axis has visual breathing room, while still keeping the
    /// current value's marker safely inside the drawn bounds even when the
    /// reading is far outside the reference range.
    private func axisBounds(range: ClosedRange<Double>, value: Double) -> (min: Double, max: Double) {
        let span = Swift.max(range.upperBound - range.lowerBound, 0.0001)
        let pad = span * 0.6
        let lower = Swift.min(range.lowerBound - pad, value - span * 0.05)
        let upper = Swift.max(range.upperBound + pad, value + span * 0.05)
        return (lower, upper)
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func detailsRows(latest: LabResult, range: ClosedRange<Double>?, reference: LabReference?) -> some View {
        if let range {
            detailRow(
                "Typical Range",
                value: "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(latest.unit)"
            )
        }
        detailRow("Unit", value: latest.unit)
        if let reference {
            detailRow("Category", value: reference.category.displayName)
        }
        detailRow("Entries", value: "\(results.count)")
    }

    private func detailRow(_ title: LocalizedStringKey, value: String) -> some View {
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

    // MARK: - History

    private func historyRow(_ result: LabResult, sex: BiologicalSex?) -> some View {
        let range = result.referenceRange(for: sex)
        let reference = result.catalogReference
        let status = AnalysisEngine.status(
            value: result.value,
            range: range,
            criticalLow: reference?.criticalLow,
            criticalHigh: reference?.criticalHigh
        )
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 14))
                    .foregroundStyle(Editorial.ink(colorScheme))
                if let title = result.report?.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(result.value.compactFormatted) \(result.unit)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Editorial.ink(colorScheme))
                EditorialTag(verbatim: status.label, kind: tagKind(for: status))
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    /// Maps a lab status to the editorial tag palette. Matches the token
    /// spec exactly: "High" reads as the cautionary amber tag, "Low" (and
    /// any critical flag) reads as the more urgent red tag.
    private func tagKind(for status: LabStatus) -> TagKind {
        switch status {
        case .normal: .good
        case .high: .warn
        case .low, .criticalLow, .criticalHigh: .bad
        case .unknown: .warn
        }
    }

    @ViewBuilder
    private func historyChart(range: ClosedRange<Double>?) -> some View {
        Chart {
            if let range {
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(Editorial.zoneIn(colorScheme).opacity(0.5))
            }
            ForEach(results) { result in
                LineMark(
                    x: .value("Date", result.date),
                    y: .value("Value", result.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Editorial.ink(colorScheme))
                PointMark(
                    x: .value("Date", result.date),
                    y: .value("Value", result.value)
                )
                .foregroundStyle(Editorial.ink(colorScheme))
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
        .chartYAxisLabel(results.last?.unit ?? "")
        .accessibilityLabel("\(results.last?.displayName ?? String(localized: "Lab result")) history chart")
    }
}
