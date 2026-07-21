import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct ReportDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [HealthProfile]
    // Additive: needed to compute "What This Scan Changed" for real (the
    // retest schedule and Action Plan count reflect the WHOLE account's
    // data, not just this one report) and to build the `HealthReview`
    // `AIChatView`'s "Ask about this report" needs.
    @Query(sort: \MedicalReport.date, order: .reverse) private var allReports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @ObservedObject private var premiumStore = PremiumStore.shared

    let report: MedicalReport

    @State private var confirmDelete = false
    @State private var showingEdit = false
    @State private var showingAIChat = false
    @State private var showingPaywall = false

    private var sex: BiologicalSex? { profiles.first?.sex }

    /// The full-account review, built the same way `ReviewScreen`/
    /// `ScanReportView` build theirs — used only by "What This Scan Changed"
    /// (for `ActionPlan.generate`) and by "Ask about this report" (for
    /// `AIChatView`), so it's a computed property rather than stored state.
    private var currentReview: HealthReview {
        AnalysisEngine.generateReview(
            profile: profiles.first,
            reports: allReports,
            vitals: vitals,
            medications: medications,
            symptoms: symptoms,
            appointments: appointments
        )
    }

    /// "Retest schedule rebuilt — next due %@", from the same
    /// `RetestSchedule.items`/`nextDraw` pipeline `RetestScheduleView` uses,
    /// over every saved report (not just this one) since a retest schedule
    /// is always account-wide.
    private var nextRetestDrawDate: Date? {
        let items = RetestSchedule.items(reports: allReports, now: .now)
        return RetestSchedule.nextDraw(items: items, now: .now)?.date
    }

    /// "Action plan — %lld supplement suggestions" — restricted to the
    /// supplement suggestions that actually trace back to one of THIS
    /// report's own out-of-range values (not every suggestion the full
    /// account-wide plan happens to carry), so the count only ever describes
    /// what this scan itself changed.
    private var actionPlanCountFromThisReport: Int {
        let thisReportSeriesKeys = Set(report.labResults.map(\.seriesKey))
        let plan = ActionPlan.generate(review: currentReview, medications: medications, now: .now)
        return plan.items.filter { thisReportSeriesKeys.contains($0.labTestID) }.count
    }

    /// "%lld trends updated" — how many of this report's own lab series now
    /// have at least 2 stored points across every saved report (i.e. a trend
    /// line actually exists to look at, the same "results.count >= 2" bar
    /// `LabDetailView` uses to decide whether to show its trend chart).
    private var trendsUpdatedCount: Int {
        let allResults = allReports.flatMap(\.labResults)
        let grouped = Dictionary(grouping: allResults, by: \.seriesKey)
        let thisReportSeriesKeys = Set(report.labResults.map(\.seriesKey))
        return thisReportSeriesKeys.filter { (grouped[$0]?.count ?? 0) >= 2 }.count
    }

    private var hasScanChanges: Bool {
        nextRetestDrawDate != nil
            || (premiumStore.isPremium && actionPlanCountFromThisReport > 0)
            || trendsUpdatedCount > 0
    }

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

            if hasScanChanges {
                Section {
                    scanChangesRows
                } header: {
                    MicroLabel("What This Scan Changed")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !report.labResults.isEmpty {
                Section {
                    askAboutReportButton
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
        .navigationTitle(bloodworkDisplayTitle(report.title))
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
        .sheet(isPresented: $showingAIChat) {
            AIChatView(review: currentReview, profileSummary: aiProfileSummary ?? "")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    // MARK: - What this scan changed

    /// Computed for real, never invented: each row only appears when its
    /// underlying computation actually has something to say (see
    /// `hasScanChanges`, `nextRetestDrawDate`, `actionPlanCountFromThisReport`,
    /// `trendsUpdatedCount` above).
    @ViewBuilder
    private var scanChangesRows: some View {
        if let nextRetestDrawDate {
            scanChangeRow(String(localized: "Retest schedule rebuilt — next due \(nextRetestDrawDate.formatted(date: .abbreviated, time: .omitted))"))
        }
        if premiumStore.isPremium && actionPlanCountFromThisReport > 0 {
            scanChangeRow(actionPlanCountFromThisReport == 1
                ? String(localized: "Action plan — 1 supplement suggestion")
                : String(localized: "Action plan — \(actionPlanCountFromThisReport) supplement suggestions"))
        }
        if trendsUpdatedCount > 0 {
            scanChangeRow(trendsUpdatedCount == 1
                ? String(localized: "1 trend updated")
                : String(localized: "\(trendsUpdatedCount) trends updated"))
        }
    }

    private func scanChangeRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("✓")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Editorial.tagGood(colorScheme))
            Text(verbatim: text)
                .font(.system(size: 14))
                .foregroundStyle(Editorial.ink(colorScheme))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Outlined "Ask about this report" — premium-gated the exact same way
    /// `ReviewScreen.aiSummaryCard`'s own chat button is: opens `AIChatView`
    /// over the full-account review when premium, otherwise the paywall.
    @ViewBuilder
    private var askAboutReportButton: some View {
        let button = Button {
            if premiumStore.isPremium {
                showingAIChat = true
            } else {
                showingPaywall = true
            }
        } label: {
            Label("Ask About This Report", systemImage: premiumStore.isPremium ? "sparkles" : "lock.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(OutlinedPillButtonStyle())

        if premiumStore.isPremium {
            button
        } else {
            button.accessibilityHint("Chat about your report is a Premium feature. Opens the upgrade screen.")
        }
    }

    /// A short, caller-built profile description, identical in spirit to
    /// `ReviewScreen.aiProfileSummary` — duplicated per this file's
    /// edit-ownership rather than shared.
    private var aiProfileSummary: String? {
        guard let profile = profiles.first else { return nil }
        var parts: [String] = []
        if let age = profile.age {
            parts.append("\(age)-year-old")
        }
        if profile.sex != .unspecified {
            parts.append(profile.sex.displayName.lowercased())
        }
        if !profile.conditions.isEmpty {
            parts.append("conditions: \(profile.conditions)")
        }
        if !profile.allergies.isEmpty {
            parts.append("allergies: \(profile.allergies)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
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
                Text(bloodworkDisplayTitle(report.title))
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

/// Display-only rename of an already-STORED report `title` from "Lab
/// Report" to "Bloodwork" — mirrors `ReportsListView`'s identical helper
/// (see that file's doc comment for the full reasoning), duplicated here
/// per this pass's file-ownership split rather than shared.
private func bloodworkDisplayTitle(_ title: String) -> String {
    let oldLabel = ReportCategory.labReport.displayName
    guard title.contains(oldLabel) else { return title }
    return title.replacingOccurrences(of: oldLabel, with: String(localized: "Bloodwork"))
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
