import SwiftUI
import SwiftData
import Charts

/// Full history and explanation for one lab test, reachable from the
/// Health Review and from report detail screens.
struct LabDetailView: View {
    let seriesKey: String

    @Query private var reports: [MedicalReport]
    @Query private var profiles: [HealthProfile]

    private var results: [LabResult] {
        reports.flatMap(\.labResults)
            .filter { $0.seriesKey == seriesKey }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if let latest = results.last {
                content(latest: latest)
            } else {
                ContentUnavailableView("No Results", systemImage: "testtube.2")
            }
        }
        .ambientScreen()
        .navigationTitle(results.last?.displayName ?? "Lab Test")
        .navigationBarTitleDisplayMode(.inline)
    }

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

        return List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(latest.value.compactFormatted) \(latest.unit)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(status.isOutOfRange ? status.color : .primary)
                        Text("Latest · \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: status.label, color: status.color)
                }
                .padding(.vertical, 4)
                if results.count >= 2 {
                    historyChart(range: range)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            if let reference {
                Section("About This Test") {
                    Text(reference.about)
                        .font(.subheadline)
                    Label {
                        Text(reference.lowMeaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Label {
                        Text(reference.highMeaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            Section("Details") {
                if let range {
                    LabeledContent(
                        "Typical Range",
                        value: "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(latest.unit)"
                    )
                }
                LabeledContent("Unit", value: latest.unit)
                if let reference {
                    LabeledContent("Category", value: reference.category.displayName)
                }
                LabeledContent("Entries", value: "\(results.count)")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section("History") {
                ForEach(results.reversed()) { result in
                    historyRow(result, sex: sex)
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
    }

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
                    .font(.subheadline)
                if let title = result.report?.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(result.value.compactFormatted) \(result.unit)")
                    .font(.subheadline.weight(.semibold))
                StatusPill(text: status.label, color: status.color)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func historyChart(range: ClosedRange<Double>?) -> some View {
        Chart {
            if let range {
                RectangleMark(
                    yStart: .value("Range low", range.lowerBound),
                    yEnd: .value("Range high", range.upperBound)
                )
                .foregroundStyle(.green.opacity(0.1))
            }
            ForEach(results) { result in
                LineMark(
                    x: .value("Date", result.date),
                    y: .value("Value", result.value)
                )
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", result.date),
                    y: .value("Value", result.value)
                )
            }
        }
        .chartYAxisLabel(results.last?.unit ?? "")
    }
}
