import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct ReportDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [HealthProfile]

    let report: MedicalReport

    @State private var confirmDelete = false
    @State private var showingEdit = false

    private var sex: BiologicalSex? { profiles.first?.sex }

    /// Every lab result evaluated against its reference range (resolved for
    /// the profile's sex, same as `LabResultRow` below), reused by the stat
    /// tiles, the "Flagged in This Report" ledger, and the full "Lab
    /// Results" list — carrying `range` alongside `status` so the flagged
    /// row's range bar uses the exact same boundaries the tag was computed
    /// from, instead of re-resolving with a different (unspecified-sex)
    /// range.
    private var evaluatedResults: [(result: LabResult, status: LabStatus, range: ClosedRange<Double>?)] {
        report.labResults.map { result in
            let range = result.referenceRange(for: sex)
            let status = AnalysisEngine.status(
                value: result.value,
                range: range,
                criticalLow: result.catalogReference?.criticalLow,
                criticalHigh: result.catalogReference?.criticalHigh
            )
            return (result, status, range)
        }
    }

    private var highCount: Int {
        evaluatedResults.filter { $0.status == .high || $0.status == .criticalHigh }.count
    }

    private var lowCount: Int {
        evaluatedResults.filter { $0.status == .low || $0.status == .criticalLow }.count
    }

    private var inRangeCount: Int {
        evaluatedResults.filter { !$0.status.isOutOfRange }.count
    }

    private var flaggedResults: [(result: LabResult, status: LabStatus, range: ClosedRange<Double>?)] {
        evaluatedResults
            .filter { $0.status.isOutOfRange }
            .sorted { $0.result.displayName < $1.result.displayName }
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            if !report.labResults.isEmpty {
                Section {
                    statTiles
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !flaggedResults.isEmpty {
                Section {
                    ForEach(flaggedResults, id: \.result.persistentModelID) { entry in
                        FlaggedLabRow(result: entry.result, status: entry.status, range: entry.range)
                    }
                } header: {
                    MicroLabel("Flagged in This Report")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !report.labResults.isEmpty {
                Section {
                    ForEach(report.labResults.sorted(by: { $0.displayName < $1.displayName })) { result in
                        NavigationLink {
                            LabDetailView(seriesKey: result.seriesKey)
                        } label: {
                            LabResultRow(result: result, sex: sex)
                        }
                    }
                } header: {
                    MicroLabel("Lab Results")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !report.attachments.isEmpty {
                Section {
                    ForEach(report.attachments) { attachment in
                        NavigationLink {
                            AttachmentViewer(attachment: attachment)
                        } label: {
                            AttachmentRow(attachment: attachment)
                        }
                    }
                } header: {
                    MicroLabel("Attachments")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !report.notes.isEmpty {
                Section {
                    Text(report.notes)
                } header: {
                    MicroLabel("Notes")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            Section {
                Button("Delete Report", role: .destructive) {
                    confirmDelete = true
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .ambientScreen()
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { showingEdit = true }
        }
        .sheet(isPresented: $showingEdit) {
            AddReportView(report: report)
        }
        .confirmationDialog(
            "Delete this report and all its results?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(report)
                dismiss()
            }
        }
    }

    // MARK: - Header

    /// Thumbnail + title + a single "date · provider · facility" source
    /// line, plus a link to the first attachment — the editorial header
    /// grammar from the report-detail mockup, replacing the old
    /// Category/Date/Provider/Facility `LabeledContent` rows.
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Editorial.insetCard(colorScheme))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1)
                Image(systemName: report.category.systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(Editorial.ink(colorScheme))
            }
            .frame(width: 56, height: 74)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.title)
                    .font(.system(size: 20, weight: .regular))
                    .tracking(-0.2)
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Editorial.muted(colorScheme))
                if let firstAttachment = report.attachments.first {
                    NavigationLink {
                        AttachmentViewer(attachment: firstAttachment)
                    } label: {
                        HStack(spacing: 3) {
                            Text("View Original")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Editorial.accent(colorScheme))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var sourceLine: String {
        var parts: [String] = [report.date.formatted(date: .long, time: .omitted)]
        if !report.facility.isEmpty {
            parts.append(report.facility)
        } else if !report.provider.isEmpty {
            parts.append(report.provider)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Stat tiles

    private var statTiles: some View {
        HStack(spacing: 8) {
            statTile(value: report.labResults.count, caption: String(localized: "Values"), color: Editorial.ink(colorScheme))
            if highCount > 0 {
                statTile(value: highCount, caption: LabStatus.high.label, color: Editorial.tagWarn(colorScheme))
            }
            if lowCount > 0 {
                statTile(value: lowCount, caption: LabStatus.low.label, color: Editorial.tagBad(colorScheme))
            }
            statTile(value: inRangeCount, caption: LabStatus.normal.label, color: Editorial.tagGood(colorScheme))
        }
    }

    private func statTile(value: Int, caption: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(Editorial.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flagged row

/// A single out-of-range value in the "Flagged in This Report" ledger:
/// name + value + tag on one line, range bar beneath — the same grammar
/// `LabResultRow` uses below, without the "typical range" caption (the
/// stat tiles above already summarize severity for the whole report).
private struct FlaggedLabRow: View {
    let result: LabResult
    let status: LabStatus
    let range: ClosedRange<Double>?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(result.value.compactFormatted) \(result.unit)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    StatusPill(text: status.label, color: status.color)
                }
            }
            if let range {
                let axis = flaggedRangeBarAxis(range: range, value: result.value)
                RangeBar(
                    lower: range.lowerBound,
                    upper: range.upperBound,
                    min: axis.min,
                    max: axis.max,
                    value: result.value,
                    accessibilityLabel: Text("\(result.displayName) \(result.value.compactFormatted) \(result.unit), \(status.label)")
                )
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }
}

/// Axis bounds for a `RangeBar` built around a reference range. `private`
/// and intentionally duplicated per file (see the identical helper in
/// `ScanReportView.swift` and `ScannedResultsSheet.swift`) rather than
/// lifted into `Support/EditorialComponents.swift`, which this agent
/// doesn't own.
private func flaggedRangeBarAxis(range: ClosedRange<Double>, value: Double) -> (min: Double, max: Double) {
    let width = range.upperBound - range.lowerBound
    let pad = width > 0 ? width * 0.35 : max(abs(range.upperBound), 1) * 0.2
    let lower = Swift.min(range.lowerBound - pad, value - pad * 0.15)
    let upper = Swift.max(range.upperBound + pad, value + pad * 0.15)
    return (lower, upper)
}

// MARK: - Lab result row

struct LabResultRow: View {
    let result: LabResult
    let sex: BiologicalSex?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let range = result.referenceRange(for: sex)
        let reference = result.catalogReference
        let status = AnalysisEngine.status(
            value: result.value,
            range: range,
            criticalLow: reference?.criticalLow,
            criticalHigh: reference?.criticalHigh
        )

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(result.value.compactFormatted) \(result.unit)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    StatusPill(text: status.label, color: status.color)
                }
            }
            if let range {
                let axis = flaggedRangeBarAxis(range: range, value: result.value)
                RangeBar(
                    lower: range.lowerBound,
                    upper: range.upperBound,
                    min: axis.min,
                    max: axis.max,
                    value: result.value,
                    accessibilityLabel: Text("\(result.displayName) \(result.value.compactFormatted) \(result.unit), \(status.label)")
                )
                Text("Typical: \(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(result.unit)")
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            if status.isOutOfRange, let reference {
                let meaning = (status == .low || status == .criticalLow)
                    ? reference.lowMeaning
                    : reference.highMeaning
                Text(meaning)
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Attachment row

/// Hairline-framed thumbnail + filename — the same "original as a
/// first-class object" treatment used in the reports library, applied to
/// this report's own attachment list.
private struct AttachmentRow: View {
    let attachment: ReportAttachment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Editorial.insetCard(colorScheme))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1)
                Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "photo")
                    .font(.system(size: 15))
                    .foregroundStyle(Editorial.ink(colorScheme))
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            Text(attachment.filename)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Editorial.ink(colorScheme))
                .lineLimit(1)
        }
        .ledgerRow()
    }
}

// MARK: - Attachment viewer

struct AttachmentViewer: View {
    let attachment: ReportAttachment

    var body: some View {
        Group {
            if attachment.kind == .pdf {
                PDFKitView(data: attachment.data)
                    .ignoresSafeArea(edges: .bottom)
            } else if let image = UIImage(data: attachment.data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .containerRelativeFrame(.horizontal)
                }
            } else {
                ContentUnavailableView("Can't Preview File", systemImage: "eye.slash")
            }
        }
        .background(AmbientBackground().accessibilityHidden(true))
        .navigationTitle(attachment.filename)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
