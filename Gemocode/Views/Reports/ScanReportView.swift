import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit
import PDFKit

/// Single-flag gate for report *creation*. Flip `reportCreation` to `false`
/// to make scanning free again — that one-line edit is the entire revert of
/// the premium gate placed around adding reports.
enum PremiumGates {
    static let reportCreation = true
}

/// Scan-only report creation: photograph or import a document, let
/// `LabScanService`'s on-device OCR find lab values automatically, confirm,
/// and save. There is no manual entry form here by design — the manual
/// form still exists for *editing* an existing report (`EditReportView`),
/// which is how users fix or fill in anything a scan missed.
///
/// Gated by `PremiumGates.reportCreation`: when the gate is on and the user
/// isn't premium, the same scan UI is shown underneath a lock card rather
/// than being replaced by a dead end, and the lock card's own button always
/// works (it opens `PaywallView`).
struct ScanReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var premiumStore = PremiumStore.shared

    // Deliberately NOT @Query: this sheet is shown while the user is
    // photographing, and a live subscription to every one of these tables
    // would re-render it on every mutation app-wide for the entire scan
    // flow, even though the data is only needed once, after save, to build
    // the post-save `HealthReview` (see `currentReview(including:)` and
    // `aiProfileSummary()` below, which fetch on demand via `modelContext`).

    @State private var attachments: [AttachmentDraft] = []
    @State private var confirmedLabs: [ScannedLabValue] = []
    @State private var scannedValues: [ScannedLabValue] = []
    /// Attachment ids already run through `LabScanService` — lets
    /// `scanAttachments()` OCR only what's new instead of re-scanning every
    /// attachment on every add. See `scanAttachments()`.
    @State private var scannedAttachmentIDs: Set<UUID> = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var showingScanResults = false
    /// The in-flight OCR task, so `.onDisappear` can cancel it if the sheet
    /// is swiped away mid-scan (see `scanAttachments()`).
    @State private var scanTask: Task<Void, Never>?
    /// Set once, in `.onDisappear`, and checked before presenting anything
    /// asynchronously (`showingScanResults`) so a torn-down view is never
    /// driven — belt-and-suspenders alongside the tasks' own cancellation.
    @State private var hasDisappeared = false

    @State private var showingPaywall = false
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var showingPhotosPicker = false
    @State private var photoItems: [PhotosPickerItem] = []

    @State private var selectedCategory: ReportCategory?

    @State private var showingCameraAlert = false
    @State private var cameraAlertMessage = ""

    // MARK: - Post-save AI stage

    /// Drives what the sheet shows after a successful save: the original
    /// scan UI, or — when `AISummaryService.isConfigured` and at least one
    /// lab value was confirmed — the auto-generated AI report in place of
    /// dismissing.
    private enum Stage {
        case scanning
        case aiGenerating
        case aiReport(AIHealthReport)
        case aiFailed(String)

        var isScanning: Bool {
            if case .scanning = self { true } else { false }
        }
    }

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var stage: Stage = .scanning
    /// The in-flight AI report generation task, so `.onDisappear` can cancel
    /// it if the sheet is swiped away mid-generation — the free trial must
    /// not be spent on a report the user never saw (see `generateAIReport`).
    @State private var aiTask: Task<Void, Never>?
    /// The report `save()` just inserted — kept so the AI stage can attach
    /// the exported PDF to it and read back its saved lab results.
    @State private var savedReport: MedicalReport?
    @State private var isPulsingAIGenerating = false
    @State private var isExportingPDF = false
    @State private var pdfExportError: String?
    @State private var shareItem: ShareItem?
    /// Cached once the AI report PDF has been rendered, so both "Share PDF"
    /// and "Open" reuse the same bytes instead of calling
    /// `AIReportPDFExporter.render` (and appending a second, duplicate
    /// `ReportAttachment`) a second time — see `renderAndAttachPDFIfNeeded()`.
    @State private var renderedPDFData: Data?
    @State private var showingPDFPreview = false
    /// Additive: the "In Range" ledger collapses beyond 3 rows until this is
    /// flipped by the "Show N more" row (see `confirmedLabsSection`).
    @State private var showAllInRangeValues = false
    /// Additive: lets the post-save AI stage link straight to the Action
    /// Plan when the just-saved report actually has an out-of-range value
    /// (see `savedReportHasOutOfRangeValue` and `aiReportActionButtons`).
    @State private var showingActionPlanFromScan = false

    /// Free users get exactly one AI scan: the same lifetime meter as the
    /// AI Health Analyst report (`AIReportQuota`), since a scan auto-runs
    /// one report. The meter is only consumed on a successful generation
    /// (see `onAIReportGenerated`), so a failed scan never costs the trial.
    private var isLocked: Bool {
        PremiumGates.reportCreation
            && !premiumStore.isPremium
            && AIReportQuota.remaining(defaults: .standard) == 0
    }

    private var canSave: Bool {
        !attachments.isEmpty && !isScanning && !isLocked
    }

    /// True once a scan has run over every current attachment and found
    /// nothing new — the trigger for the category fallback chips and the
    /// "couldn't find lab values" note.
    private var nothingExtracted: Bool {
        hasScanned && !isScanning && confirmedLabs.isEmpty && scannedValues.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    stageContent
                }
                .padding()
            }
            .ambientScreen()
            .navigationTitle(stage.isScanning ? "New Report" : "AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage.isScanning {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingScanResults) {
                ScannedResultsSheet(values: scannedValues) { selected in
                    // Move the confirmed values out of `scannedValues` (not
                    // just append into `confirmedLabs`) — otherwise the next
                    // page's scan still finds these already-confirmed values
                    // sitting in `scannedValues` and re-offers/re-appends
                    // them, duplicating LabResult rows on save. Match by the
                    // same identity `scanAttachments()`'s dedupe uses:
                    // `reference.id.lowercased()`.
                    let selectedKeys = Set(selected.map { $0.reference.id.lowercased() })
                    confirmedLabs.append(contentsOf: selected)
                    scannedValues.removeAll { selectedKeys.contains($0.reference.id.lowercased()) }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { data in
                    attachments.append(AttachmentDraft(
                        filename: "Photo \(attachments.count + 1)",
                        kind: .image,
                        data: data
                    ))
                    scanAttachments()
                }
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true,
                onCompletion: handleFileImport
            )
            .photosPicker(isPresented: $showingPhotosPicker, selection: $photoItems, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
            .alert("Camera", isPresented: $showingCameraAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraAlertMessage)
            }
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(activityItems: [item.url]) {
                    shareItem = nil
                }
            }
            .onDisappear {
                // The sheet was dismissed (swipe-to-dismiss or programmatic)
                // while a scan or an AI generation was still running. Cancel
                // both in-flight tasks and flag the view as gone so neither
                // completion handler mutates state or presents anything —
                // in particular, the AI free-trial quota must not be
                // recorded for a report the user never actually saw.
                hasDisappeared = true
                aiTask?.cancel()
                scanTask?.cancel()
            }
        }
    }

    // MARK: - Content

    /// Top-level switch between the original scan UI and the post-save AI
    /// stage — exactly one is shown at a time, driven by `stage`.
    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .scanning:
            Group {
                ScanReportHeader()

                if isLocked {
                    // Nulled: an ambient transaction already in flight when
                    // this appears (e.g. the camera sheet dismissing, or
                    // `premiumStore` publishing its async-loaded entitlement
                    // moments after appear) must not be inherited by this
                    // ZStack's insertion — same reasoning as ReviewScreen's
                    // cards.
                    ZStack {
                        unlockedBody
                            .disabled(true)
                            .opacity(0.28)
                            .accessibilityHidden(true)
                        lockedCard
                    }
                    .transaction { $0.animation = nil }
                } else {
                    unlockedBody
                        .transaction { $0.animation = nil }
                }
            }
        case .aiGenerating, .aiReport, .aiFailed:
            aiStageBody
        }
    }

    @ViewBuilder
    private var unlockedBody: some View {
        VStack(spacing: 16) {
            scanActions

            if isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning for lab values…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
                .transaction { $0.animation = nil }
            }

            if !attachments.isEmpty {
                attachmentsSection
                    .transaction { $0.animation = nil }
            }

            if !confirmedLabs.isEmpty {
                confirmedLabsSection
                saveValuesButton
            }

            if !scannedValues.isEmpty {
                reviewButton
                    .transaction { $0.animation = nil }
            }

            if nothingExtracted {
                categoryFallbackSection
                    .transaction { $0.animation = nil }
            }

            if !attachments.isEmpty {
                Text("You can rename or edit details any time from the report's Edit button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var scanActions: some View {
        Button {
            presentCamera()
        } label: {
            ScanActionCard(
                icon: "camera.fill",
                title: "Photograph a Document",
                subtitle: "Use your camera to capture a lab report"
            )
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
        .accessibilityLabel("Photograph a document")
        .accessibilityHint("Opens the camera to capture a lab report.")

        Menu {
            Button {
                showingPhotosPicker = true
            } label: {
                Label("Photo from Library", systemImage: "photo.on.rectangle")
            }
            Button {
                showingFileImporter = true
            } label: {
                Label("PDF File", systemImage: "doc.richtext")
            }
        } label: {
            ScanActionCard(
                icon: "square.and.arrow.down.on.square",
                title: "Import PDF or Photo",
                subtitle: "Choose an existing file from your library"
            )
        }
        .disabled(isScanning)
        .accessibilityLabel("Import PDF or photo")
        .accessibilityHint("Choose a PDF or photo already saved on your device.")
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Attached", systemImage: "paperclip")
                .font(.subheadline.weight(.semibold))
            ForEach(attachments) { attachment in
                HStack {
                    Label(
                        attachment.filename,
                        systemImage: attachment.kind == .pdf ? "doc.richtext" : "photo"
                    )
                    .font(.subheadline)
                    Spacer()
                    Button {
                        removeAttachment(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(attachment.filename)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Every confirmed value gets the shared "name, value, tag, bar" ledger
    /// grammar, grouped into an "Out of Range" ledger (full row: tag + bar +
    /// range caption) and an "In Range" ledger (a quieter, compact row) —
    /// exactly the two-tier layout the scan-result mockups use. The header
    /// card above it, and the "Show N more" collapse on the in-range list
    /// below, are additive presentation on top of the same evaluated list.
    private var confirmedLabsSection: some View {
        let sex = fetchProfile()?.sex
        let evaluated = confirmedLabs.map { scanned -> (scanned: ScannedLabValue, status: LabStatus, range: ClosedRange<Double>?) in
            let range = scanned.reference.referenceRange(for: sex)
            let status = AnalysisEngine.status(
                value: scanned.value,
                range: range,
                criticalLow: scanned.reference.criticalLow,
                criticalHigh: scanned.reference.criticalHigh
            )
            return (scanned, status, range)
        }
        let outOfRange = evaluated.filter { $0.status.isOutOfRange }
        let inRangeList = evaluated.filter { !$0.status.isOutOfRange }
        let visibleInRange = showAllInRangeValues ? inRangeList : Array(inRangeList.prefix(3))
        let hiddenInRangeCount = inRangeList.count - visibleInRange.count
        let priorValues = fetchLatestPriorValues()
        let supplementSuggestedIDs = supplementSuggestedLabIDs(for: evaluated)

        return VStack(alignment: .leading, spacing: 4) {
            scannedAttachmentHeaderCard(valuesRead: confirmedLabs.count)
                .padding(.bottom, 12)

            if !outOfRange.isEmpty {
                MicroLabel("Out of range · \(outOfRange.count)")
                VStack(spacing: 0) {
                    ForEach(outOfRange, id: \.scanned.id) { entry in
                        confirmedLabRow(
                            entry,
                            compact: false,
                            priorValue: priorValues[entry.scanned.reference.id.lowercased()],
                            supplementSuggested: supplementSuggestedIDs.contains(entry.scanned.reference.id.lowercased())
                        )
                    }
                }
            }
            if !inRangeList.isEmpty {
                MicroLabel("In range · \(inRangeList.count)")
                    .padding(.top, outOfRange.isEmpty ? 0 : 16)
                VStack(spacing: 0) {
                    ForEach(visibleInRange, id: \.scanned.id) { entry in
                        confirmedLabRow(entry, compact: true, priorValue: nil, supplementSuggested: false)
                    }
                }
                if hiddenInRangeCount > 0 {
                    Button {
                        withAnimation { showAllInRangeValues = true }
                    } label: {
                        Text("Show \(hiddenInRangeCount) more ↗")
                            .font(.system(size: 12))
                            .foregroundStyle(Editorial.accent(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityLabel("Show \(hiddenInRangeCount) more in-range values")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The scan-result header card: a document-style thumbnail, the report
    /// title/date this save will use (mirrors `save()`'s own title-building —
    /// see that function's doc comment on why "today" stands in for a real
    /// document date), a "%lld values read · original kept" line, and a
    /// small "Read" tag. Shown once at least one value has been confirmed —
    /// before that there's nothing yet to summarize.
    private func scannedAttachmentHeaderCard(valuesRead: Int) -> some View {
        let title = "\(ReportCategory.labReport.displayName) — \(Date.now.formatted(date: .abbreviated, time: .omitted))"
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Editorial.canvas(colorScheme))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1)
                Image(systemName: ReportCategory.labReport.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(Editorial.ink(colorScheme))
            }
            .frame(width: 34, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Text("\(valuesRead) values read · original kept")
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            Spacer(minLength: 8)
            EditorialTag("✓ Read", kind: .good)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(valuesRead) values read, original kept, read")
    }

    /// One-shot fetch of the latest saved value per lab series across every
    /// already-saved report — used only to show "up from X" / "down from X"
    /// on a just-scanned value. Mirrors the seriesKey-based grouping
    /// `TrendsView`/`LabDetailView` use for their own history lookups, but as
    /// a single read-only fetch rather than a live `@Query` — this sheet
    /// deliberately avoids `@Query` (see the type-level comment above), and
    /// nothing here has been saved yet, so there's no live state to observe.
    private func fetchLatestPriorValues() -> [String: Double] {
        let allResults = (try? modelContext.fetch(FetchDescriptor<LabResult>())) ?? []
        let grouped = Dictionary(grouping: allResults, by: \.seriesKey)
        return grouped.compactMapValues { $0.max(by: { $0.date < $1.date })?.value }
    }

    /// Which of the currently-evaluated scanned values would surface an
    /// `ActionPlan` supplement suggestion, keyed by lowercased catalog id.
    /// Built by handing a minimal, throwaway `HealthReview` (just today's
    /// scanned snapshots — no findings/trends/score, none of which
    /// `ActionPlan.generate` reads) to the real `ActionPlan.generate` rule
    /// table, so "supplement suggested" always reflects the actual rules in
    /// `Services/ActionPlan.swift` rather than a duplicated whitelist here.
    private func supplementSuggestedLabIDs(
        for evaluated: [(scanned: ScannedLabValue, status: LabStatus, range: ClosedRange<Double>?)]
    ) -> Set<String> {
        let snapshots = evaluated.map { entry in
            LabSnapshot(
                id: entry.scanned.reference.id.lowercased(),
                name: entry.scanned.reference.name,
                unit: entry.scanned.reference.unit,
                value: entry.scanned.value,
                date: .now,
                status: entry.status,
                range: entry.range,
                reference: entry.scanned.reference
            )
        }
        let miniReview = HealthReview(
            generatedAt: .now,
            hasData: true,
            score: 0,
            summary: "",
            findings: [],
            trends: [],
            labSnapshots: snapshots
        )
        let plan = ActionPlan.generate(review: miniReview, medications: [], now: .now)
        return Set(plan.items.map(\.labTestID))
    }

    /// A single confirmed-value row. The full (`compact: false`) form shows
    /// name + value + tag on one line and the range bar beneath it — used
    /// for out-of-range values. The compact form drops the tag (the section
    /// header already says "In Range") and shows a slimmer inline bar next
    /// to the value, matching the quieter in-range ledger in the mockups.
    /// `priorValue`/`supplementSuggested` only ever feed the full form's
    /// caption line — the compact in-range rows never pass them.
    @ViewBuilder
    private func confirmedLabRow(
        _ entry: (scanned: ScannedLabValue, status: LabStatus, range: ClosedRange<Double>?),
        compact: Bool,
        priorValue: Double?,
        supplementSuggested: Bool
    ) -> some View {
        if compact {
            HStack(spacing: 12) {
                Text(entry.scanned.reference.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let range = entry.range {
                    let axis = rangeBarAxis(range: range, value: entry.scanned.value)
                    RangeBar(
                        lower: range.lowerBound,
                        upper: range.upperBound,
                        min: axis.min,
                        max: axis.max,
                        value: entry.scanned.value
                    )
                    .frame(width: 70)
                }
                Text("\(entry.scanned.value.compactFormatted) \(entry.scanned.reference.unit)")
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            .ledgerRow()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.scanned.reference.name), \(entry.scanned.value.compactFormatted) \(entry.scanned.reference.unit), \(entry.status.label)")
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.scanned.reference.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(entry.scanned.value.compactFormatted) \(entry.scanned.reference.unit)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        StatusPill(text: entry.status.label, color: entry.status.color)
                    }
                }
                if let range = entry.range {
                    let axis = rangeBarAxis(range: range, value: entry.scanned.value)
                    RangeBar(
                        lower: range.lowerBound,
                        upper: range.upperBound,
                        min: axis.min,
                        max: axis.max,
                        value: entry.scanned.value,
                        accessibilityLabel: Text("\(entry.scanned.reference.name) \(entry.scanned.value.compactFormatted) \(entry.scanned.reference.unit), \(entry.status.label)")
                    )
                    if let caption = scannedRowCaption(range: range, priorValue: priorValue, currentValue: entry.scanned.value, supplementSuggested: supplementSuggested) {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
            }
            .ledgerRow()
        }
    }

    /// Builds the "lab range %@–%@ · ↗ up from %@ · supplement suggested"
    /// caption for one out-of-range confirmed row. Every clause is optional
    /// and only appears when there's real data behind it: the trend clause
    /// needs an actual prior saved value for this series, and the supplement
    /// clause needs this id to actually be one of `ActionPlan`'s rules (see
    /// `supplementSuggestedLabIDs(for:)`).
    private func scannedRowCaption(
        range: ClosedRange<Double>,
        priorValue: Double?,
        currentValue: Double,
        supplementSuggested: Bool
    ) -> String? {
        var parts: [String] = [
            String(localized: "lab range \(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted)")
        ]
        if let priorValue, priorValue != currentValue {
            parts.append(
                currentValue > priorValue
                    ? String(localized: "↗ up from \(priorValue.compactFormatted)")
                    : String(localized: "↘ down from \(priorValue.compactFormatted)")
            )
        }
        if supplementSuggested {
            parts.append(String(localized: "supplement suggested"))
        }
        return parts.joined(separator: " · ")
    }

    /// The prominent, full-width "Save N values" confirmation — the one
    /// filled-accent CTA for this screen, mirroring the scan-result mockups'
    /// bottom button. Wired to the exact same `save()`/`canSave` gating as
    /// the toolbar Save button; this is purely an additional, more
    /// discoverable affordance for the same action.
    private var saveValuesButton: some View {
        Button {
            save()
        } label: {
            Text(confirmedLabs.count == 1
                ? String(localized: "Save \(confirmedLabs.count) Value")
                : String(localized: "Save \(confirmedLabs.count) Values"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassProminentButtonStyle())
        .disabled(!canSave)
    }

    private var reviewButton: some View {
        Button {
            showingScanResults = true
        } label: {
            Label(
                scannedValues.count == 1
                    ? String(localized: "Review \(scannedValues.count) Detected Value")
                    : String(localized: "Review \(scannedValues.count) Detected Values"),
                systemImage: "checkmark.circle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var categoryFallbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "We couldn't find lab values in this document — that's OK, it was saved with your attachment.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("What kind of report is this?")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportCategory.allCases) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var lockedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            MicroLabel("Premium")
            Text("Scan Lab Reports with Premium")
                .font(.headline)
            Text("Photograph or import a lab report and Gemocode extracts your results automatically — no manual typing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("You've used your free AI scan. Premium unlocks unlimited scans and AI reports.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                showingPaywall = true
            } label: {
                Text("Unlock Premium")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan lab reports with Premium. Photograph or import a lab report and Gemocode extracts your results automatically. You've used your free AI scan; Premium unlocks unlimited scans and AI reports.")
        .accessibilityHint("Double tap Unlock Premium to see plans.")
    }

    // MARK: - AI Analysis stage

    @ViewBuilder
    private var aiStageBody: some View {
        switch stage {
        case .scanning:
            EmptyView()
        case .aiGenerating:
            aiGeneratingHeader
            aiGeneratingCard
        case .aiReport:
            healthReportHeader
            aiReportPreviewCard
            aiReportChecklist
            aiReportActionButtons
            if savedReportHasOutOfRangeValue {
                actionPlanLinkButton
            }
            if !premiumStore.isPremium {
                Text("Your first report is free — this one used your lifetime trial.")
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        case .aiFailed(let message):
            aiGeneratingHeader
            aiErrorCard(message)
            doneButton
        }
    }

    /// The plain "we're working on it" / "something went wrong" header —
    /// shown for `.aiGenerating` and `.aiFailed`. The successful `.aiReport`
    /// stage uses `healthReportHeader` instead (see below): only once a
    /// verified report exists is there a real generated-at date and PDF to
    /// describe.
    private var aiGeneratingHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            Text("AI Health Analyst")
                .font(.title2.bold())
            Text("Your scan was saved — here's an AI-assisted read of what it means.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var aiGeneratingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Generating your AI report…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(isPulsingAIGenerating ? 1 : 0.6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isPulsingAIGenerating = true
                    }
                }
                .onDisappear { isPulsingAIGenerating = false }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - "Health report" presentation (6s)

    /// Left-aligned "Health report" title + "Generated <date> · structured
    /// PDF for your doctor" subtitle — the editorial-title treatment used
    /// once a verified `AIHealthReport` actually exists to describe.
    private var healthReportHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health report")
                .font(.system(size: 30, weight: .regular))
                .tracking(-0.6)
                .foregroundStyle(Editorial.ink(colorScheme))
            Text("Generated \(Date.now.formatted(date: .abbreviated, time: .omitted)) · structured PDF for your doctor")
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A stylized, non-functional miniature of the real exported PDF — ink
    /// lines/blocks standing in for its sections, NOT a live render of
    /// `AIReportPDFExporter`'s actual output. Always paper-white regardless
    /// of color scheme (it depicts a physical printed page), and hidden from
    /// VoiceOver since it carries no real information — the two checklist
    /// lines below it, and the PDF itself via Share/Open, are what's real.
    private var aiReportPreviewCard: some View {
        let profileName = fetchProfile()?.name ?? ""
        let dateText = Date.now.formatted(date: .abbreviated, time: .omitted)
        let subtitleText = profileName.isEmpty ? dateText : "\(profileName) — \(dateText)"

        return VStack(alignment: .leading, spacing: 5) {
            Text("GEMOCODE · HEALTH REPORT")
                .font(.system(size: 8, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color(white: 0.55))
            Text(verbatim: subtitleText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.1))
            Rectangle().fill(Color(white: 0.88)).frame(height: 1).padding(.vertical, 3)

            previewSectionLabel("SUMMARY")
            previewBar(width: 0.92)
            previewBar(width: 0.84)
            previewBar(width: 0.88)

            previewSectionLabel("OUT OF RANGE").padding(.top, 4)
            HStack(spacing: 4) {
                Capsule().fill(Editorial.tagWarn(.light)).frame(width: 44, height: 4)
                Capsule().fill(Color(white: 0.94)).frame(height: 4)
            }
            HStack(spacing: 4) {
                Capsule().fill(Editorial.tagBad(.light)).frame(width: 34, height: 4)
                Capsule().fill(Color(white: 0.94)).frame(height: 4)
            }

            previewSectionLabel("DISCUSS WITH YOUR DOCTOR").padding(.top, 4)
            previewBar(width: 0.9)
            previewBar(width: 0.7)

            Text("Page 1 · educational, not diagnostic")
                .font(.system(size: 6))
                .foregroundStyle(Color(white: 0.55))
                .padding(.top, 6)
        }
        .padding(14)
        .frame(width: 200, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 6)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }

    private func previewSectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Color(white: 0.55))
    }

    private func previewBar(width: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Color(white: 0.94))
                .frame(width: geometry.size.width * width, height: 4)
        }
        .frame(height: 4)
    }

    /// The two real, data-driven claims about what's inside the PDF —
    /// everything else on `aiReportPreviewCard` is decorative.
    private var aiReportChecklist: some View {
        let valueCount = savedReport?.labResults.count ?? 0
        let summaryLine = valueCount == 1
            ? String(localized: "Plain-words summary of your \(valueCount) value")
            : String(localized: "Plain-words summary of all \(valueCount) values")
        return VStack(alignment: .leading, spacing: 4) {
            aiChecklistLine(summaryLine)
            aiChecklistLine(String(localized: "Trends, medications and questions to ask"))
        }
    }

    private func aiChecklistLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("✓")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Editorial.tagGood(colorScheme))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Editorial.ink(colorScheme))
        }
        .accessibilityElement(children: .combine)
    }

    /// "Share PDF" (filled) + "Open" (outlined) — both reuse
    /// `renderAndAttachPDFIfNeeded()`, the same `AIReportPDFExporter.render`
    /// call and report-attachment write the old single "Save as PDF" button
    /// used; this only adds a second, in-app preview action on top.
    private var aiReportActionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    shareAIReportPDF()
                } label: {
                    Text(isExportingPDF ? "Preparing…" : "Share PDF")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassProminentButtonStyle())
                .disabled(isExportingPDF)

                Button {
                    openAIReportPDF()
                } label: {
                    Text("Open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(isExportingPDF)
            }

            if let pdfExportError {
                Text(pdfExportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            doneButton
        }
        .sheet(isPresented: $showingPDFPreview) {
            NavigationStack {
                PDFKitView(data: renderedPDFData ?? Data())
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("AI Health Analysis")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingPDFPreview = false }
                        }
                    }
            }
        }
    }

    /// True once the just-saved report has at least one out-of-range lab
    /// value — the trigger for the "View Action Plan" link right below the
    /// Share/Open buttons (see `ActionPlanView`, which only ever has
    /// something to suggest for out-of-range values in the first place).
    private var savedReportHasOutOfRangeValue: Bool {
        guard let savedReport else { return false }
        let sex = fetchProfile()?.sex
        return savedReport.labResults.contains { result in
            AnalysisEngine.status(
                value: result.value,
                range: result.referenceRange(for: sex),
                criticalLow: result.catalogReference?.criticalLow,
                criticalHigh: result.catalogReference?.criticalHigh
            ).isOutOfRange
        }
    }

    private var actionPlanLinkButton: some View {
        Button {
            showingActionPlanFromScan = true
        } label: {
            Label("View Action Plan", systemImage: "checklist")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
        .sheet(isPresented: $showingActionPlanFromScan) {
            if let savedReport {
                ActionPlanView(review: currentReview(including: savedReport), scanDate: savedReport.date)
            }
        }
    }

    private func aiErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Report Unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Your scan and lab values are safely saved either way.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
    }

    // MARK: - Attachment ingestion (mirrors EditReportView's working patterns)

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var addedAny = false
        for item in items {
            if let raw = try? await item.loadTransferable(type: Data.self) {
                // Downsampling is pure and off-main (ImageDownsampler decodes
                // via ImageIO's thumbnail pipeline, never a full-resolution
                // bitmap); never inflates, and falls back to the original
                // bytes if the source isn't a decodable image.
                let data = await Task.detached {
                    ImageDownsampler.downsampledJPEG(from: raw) ?? raw
                }.value
                attachments.append(AttachmentDraft(
                    filename: "Photo \(attachments.count + 1)",
                    kind: .image,
                    data: data
                ))
                addedAny = true
            }
        }
        photoItems = []
        if addedAny { scanAttachments() }
    }

    // `.fileImporter` above is restricted to `allowedContentTypes: [.pdf]`,
    // so every attachment built here is `kind: .pdf` — no downsampling path
    // applies (`ImageDownsampler` is for `.image` attachments only).
    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var addedAny = false
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: url) {
                attachments.append(AttachmentDraft(
                    filename: url.lastPathComponent,
                    kind: .pdf,
                    data: data
                ))
                addedAny = true
            }
        }
        if addedAny { scanAttachments() }
    }

    private func removeAttachment(_ attachment: AttachmentDraft) {
        attachments.removeAll { $0.id == attachment.id }
        if attachments.isEmpty {
            scannedValues = []
            hasScanned = false
            scannedAttachmentIDs = []
        } else {
            // Removal has no per-attachment provenance for `scannedValues`
            // (a value found earlier might have come from the attachment
            // that's leaving), so — same as before this fix — fall back to
            // a full rescan of what remains rather than risk stale values.
            // This is the rare "remove" path, not the hot "keep
            // photographing pages" path `scanAttachments()` optimizes below.
            scannedAttachmentIDs = []
            scannedValues = []
            scanAttachments()
        }
    }

    /// Runs `LabScanService` only over attachments not yet OCR'd (tracked by
    /// `scannedAttachmentIDs`), instead of re-scanning every attachment on
    /// every add — the previous behavior re-ran Vision OCR over the whole
    /// growing attachment list each time a page was photographed. Values
    /// already confirmed, or already sitting unconfirmed in `scannedValues`
    /// from an earlier scan, are filtered out of the newly found results
    /// before merging so repeat scans accumulate rather than duplicate —
    /// preserving the same "no duplicate detected value" behavior the old
    /// full-replace (`scannedValues = found`) approach had for free.
    private func scanAttachments() {
        // Re-entrancy guard: a second trigger while OCR is still running
        // (e.g. rapid camera taps landing before the buttons' `.disabled`
        // takes effect) must not start a second concurrent scan. Nothing is
        // queued — the user can rescan once the in-flight pass finishes.
        guard !isScanning else { return }
        let unscanned = attachments.filter { !scannedAttachmentIDs.contains($0.id) }
        guard !unscanned.isEmpty else { return }
        isScanning = true
        let inputs = unscanned.map { (kind: $0.kind, data: $0.data) }
        let newlyScannedIDs = Set(unscanned.map { $0.id })
        let existingKeys = Set(confirmedLabs.map { $0.reference.id.lowercased() })
            .union(scannedValues.map { $0.reference.id.lowercased() })
        scanTask = Task {
            let found = await LabScanService.scan(attachments: inputs)
                .filter { !existingKeys.contains($0.reference.id.lowercased()) }
            // Cancelled (sheet dismissed mid-OCR, see .onDisappear below) —
            // skip every mutation, including `isScanning`/`hasScanned`,
            // rather than update state on a view that's gone.
            guard !Task.isCancelled else { return }
            scannedValues.append(contentsOf: found)
            scannedAttachmentIDs.formUnion(newlyScannedIDs)
            isScanning = false
            hasScanned = true
            // Belt-and-suspenders on top of the cancellation guard above:
            // never present a sheet once the view has already torn down.
            if !found.isEmpty && !hasDisappeared {
                showingScanResults = true
            }
        }
    }

    // MARK: - Camera permission

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlertMessage = String(localized: "This device doesn't have a camera available. Use Import PDF or Photo instead.")
            showingCameraAlert = true
            return
        }
        // This build doesn't yet declare NSCameraUsageDescription in
        // Info.plist — presenting the camera without it would crash at the
        // OS level. Fail soft to the alert instead until that key is added.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            cameraAlertMessage = String(localized: "Camera access isn't configured in this build yet. Use Import PDF or Photo instead.")
            showingCameraAlert = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingCamera = true
                    } else {
                        cameraAlertMessage = String(localized: "Camera access was denied. Enable it in Settings, or use Import PDF or Photo instead.")
                        showingCameraAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = String(localized: "Camera access is disabled for Gemocode. Enable it in Settings, or use Import PDF or Photo instead.")
            showingCameraAlert = true
        @unknown default:
            cameraAlertMessage = String(localized: "Camera access isn't available. Use Import PDF or Photo instead.")
            showingCameraAlert = true
        }
    }

    // MARK: - Save

    /// Stable identifier for the 90-day re-test nudge, so scheduling it
    /// again (from a later new report) replaces rather than stacks. This is
    /// the sole "new report" creation path now, so this lives here instead
    /// of `EditReportView`.
    private static let retestNudgeID = "retest.nudge"

    /// Zero manual fields: category is `.labReport` whenever any lab value
    /// was confirmed, otherwise the fallback chip selection (defaulting to
    /// `.other` if the user never picked one — never a required step that
    /// could trap the save). Title is generated from that category and
    /// today's date; `LabScanService` doesn't expose a document date to
    /// parse, so "today" is what's used.
    private func save() {
        guard canSave else { return }
        let now = Date.now
        let category = confirmedLabs.isEmpty ? (selectedCategory ?? .other) : .labReport
        let title = "\(category.displayName) — \(now.formatted(date: .abbreviated, time: .omitted))"

        let report = MedicalReport(title: title, category: category, date: now)
        modelContext.insert(report)

        // Defensive dedupe: the ScannedResultsSheet onAdd handler already
        // removes confirmed values from `scannedValues` so a second scan
        // can't re-offer and re-append them, but this is the last line of
        // defense against any path double-writing the same lab value into
        // one report — keep the first occurrence of each catalog id.
        var seenLabKeys: Set<String> = []
        let dedupedLabs = confirmedLabs.filter { seenLabKeys.insert($0.reference.id.lowercased()).inserted }

        for scanned in dedupedLabs {
            report.labResults.append(LabResult(
                catalogID: scanned.reference.id,
                value: scanned.value,
                unit: scanned.reference.unit,
                date: now
            ))
        }

        for draft in attachments {
            report.attachments.append(ReportAttachment(
                filename: draft.filename,
                kind: draft.kind,
                data: draft.data
            ))
        }

        if !report.labResults.isEmpty {
            scheduleRetestNudge()
        }

        Haptics.success()

        // Auto-run the AI Health Analyst on the just-saved scan whenever a
        // lab value was confirmed and AI is reachable, instead of
        // dismissing — see `generateAIReport(for:)` below. Otherwise this
        // is the original, unchanged save-and-dismiss behavior.
        if !report.labResults.isEmpty, AISummaryService.isConfigured {
            savedReport = report
            generateAIReport(for: report)
        } else {
            dismiss()
        }
    }

    /// Nudges the user to re-test after they log a new report that includes
    /// at least one lab result. When the confirmed labs include catalog ids
    /// with a known `RetestSchedule` interval, the SHORTEST such interval
    /// sets the nudge date — e.g. a panel mixing an annual lipid test with a
    /// 6-month HbA1c nudges at 6 months, since that's the soonest anything
    /// in this report is next due. Otherwise this falls back to the
    /// original ~90-day (3-month) wellness nudge. Neutral, non-urgent copy —
    /// a wellness nudge, not medical advice, and `RetestSchedule`'s
    /// intervals are commonly recommended cadences, not a personalized
    /// schedule. Replaces any previously scheduled nudge so only the most
    /// recent lab report restarts the countdown.
    private func scheduleRetestNudge() {
        NotificationService.cancelReminder(id: Self.retestNudgeID)

        let knownIntervalMonths = confirmedLabs.compactMap { RetestSchedule.intervalMonths(for: $0.reference.id) }
        let fireDate: Date
        let intervalDescription: String
        if let shortestMonths = knownIntervalMonths.min() {
            fireDate = Calendar.current.date(byAdding: .month, value: shortestMonths, to: .now)
                ?? .now.addingTimeInterval(Double(shortestMonths) * 30 * 86_400)
            intervalDescription = shortestMonths == 1
                ? String(localized: "1 month")
                : String(localized: "\(shortestMonths) months")
        } else {
            fireDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now.addingTimeInterval(90 * 86_400)
            intervalDescription = String(localized: "\(3) months")
        }

        Task {
            if await NotificationService.requestAuthorization() {
                NotificationService.scheduleOneTime(
                    id: Self.retestNudgeID,
                    title: String(localized: "Time for a Follow-Up?"),
                    body: String(localized: "It's been \(intervalDescription) since your last lab report — re-test to see your trend."),
                    at: fireDate
                )
            }
        }
    }

    // MARK: - AI report generation

    /// One-shot lookup of the single `HealthProfile` — replaces the removed
    /// `@Query private var profiles`. Shared by `currentReview(including:)`,
    /// `aiProfileSummary()`, and `renderAndAttachPDFIfNeeded()` so there's
    /// exactly one place that knows how to fetch it.
    private func fetchProfile() -> HealthProfile? {
        (try? modelContext.fetch(FetchDescriptor<HealthProfile>()))?.first
    }

    /// A short, caller-built profile description ("42-year-old male;
    /// conditions: hypertension"). Identical to `ReviewScreen.aiProfileSummary`
    /// in spirit — duplicated rather than shared, per this file's
    /// edit-ownership: this view has no shared AI-helper module of its own
    /// to put it in. A function rather than a computed property now that it
    /// fetches (see `fetchProfile()`) instead of reading a live `@Query`.
    private func aiProfileSummary() -> String? {
        guard let profile = fetchProfile() else { return nil }
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

    /// `AnalysisEngine.generateReview` over every record, fetched one-shot
    /// from `modelContext` (see the removed `@Query` properties above),
    /// patched to guarantee `savedReport` is included even on the very first
    /// call right after `save()` inserts it — a fetch immediately after
    /// insert isn't guaranteed to observe it yet. Every fetch degrades to an
    /// empty array on failure (`try?`) rather than throwing, so a fetch
    /// hiccup only thins out the AI report input instead of crashing the
    /// just-completed save.
    private func currentReview(including savedReport: MedicalReport) -> HealthReview {
        var allReports = (try? modelContext.fetch(
            FetchDescriptor<MedicalReport>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )) ?? []
        if !allReports.contains(where: { $0.persistentModelID == savedReport.persistentModelID }) {
            allReports.append(savedReport)
        }
        let vitals = (try? modelContext.fetch(FetchDescriptor<VitalSample>())) ?? []
        let medications = (try? modelContext.fetch(FetchDescriptor<Medication>())) ?? []
        let symptoms = (try? modelContext.fetch(FetchDescriptor<SymptomEntry>())) ?? []
        let appointments = (try? modelContext.fetch(
            FetchDescriptor<Appointment>(sortBy: [SortDescriptor(\.date)])
        )) ?? []
        return AnalysisEngine.generateReview(
            profile: fetchProfile(),
            reports: allReports,
            vitals: vitals,
            medications: medications,
            symptoms: symptoms,
            appointments: appointments
        )
    }

    /// Runs the same `AnalysisEngine.generateReview` → `AISummaryService.generateReport`
    /// pipeline `ReviewScreen` uses, over the just-saved report plus every
    /// other fetched record. Never blocks or loses the scan: the report was
    /// already saved before this is called, and any failure or refusal here
    /// just shows a friendly inline error next to the `Done` button.
    ///
    /// `currentReview`/`aiProfileSummary` are called inside the `Task`
    /// (rather than synchronously before it, as before) purely so SwiftUI
    /// gets a chance to paint the just-set `.aiGenerating` stage first —
    /// both remain main-actor work either way, since `modelContext` fetches
    /// and `HealthReview`/`MedicalReport` are all main-actor-pinned.
    private func generateAIReport(for report: MedicalReport) {
        stage = .aiGenerating

        aiTask = Task {
            let review = currentReview(including: report)
            let profileSummary = aiProfileSummary()
            do {
                let generated = try await AISummaryService.generateReport(
                    review: review,
                    profileSummary: profileSummary,
                    deltas: []
                )
                // Sheet was dismissed while the request was in flight — do
                // NOT set `stage` (there's no view left to show it) and, in
                // particular, do NOT call `onAIReportGenerated()`: the free
                // lifetime AI trial must only be spent when the user
                // actually saw the result, not for a report generated after
                // they'd already swiped the sheet away.
                guard !Task.isCancelled else { return }
                Haptics.success()
                stage = .aiReport(generated)
                await onAIReportGenerated()
            } catch {
                guard !Task.isCancelled else { return }
                stage = .aiFailed(error.localizedDescription)
            }
        }
    }

    /// Metering hook: called once, right after an auto-generated AI report
    /// is produced and has passed `AISummaryService`'s verification guards.
    /// Mirrors `ReviewScreen`: the free trial is only spent on success, and
    /// entitlements are resolved first so a paying subscriber whose
    /// StoreKit state hasn't loaded yet never burns the trial.
    private func onAIReportGenerated() async {
        await premiumStore.ensureEntitlementsLoaded()
        if !premiumStore.isPremium {
            AIReportQuota.recordUse(defaults: .standard)
        }
    }

    // MARK: - PDF export

    /// "Save as PDF": renders the verified AI report, attaches it to the
    /// already-saved `MedicalReport` as a `ReportAttachment` (so it shows up
    /// in the Documents library), then opens the system share sheet with
    /// the file. The attachment is kept even if the user cancels or the
    /// share sheet itself can't be prepared — only rendering can fail this
    /// early, and that's surfaced inline via `pdfExportError`.
    ///
    /// `AIReportPDFExporter.render` takes SwiftData model objects directly
    /// (`scannedLabs: [LabResult]`, and `HealthReview` is built from model
    /// data too) — SwiftData models aren't `Sendable` and stay pinned to
    /// this context's actor (main), so genuinely moving the render off-main
    /// would require the exporter's API to accept `Sendable` value-type
    /// snapshots instead, which is a larger change than this fix covers.
    /// The minimal, actor-safe improvement taken here: do the work inside a
    /// `Task { @MainActor in ... }` with an `await Task.yield()` right after
    /// `isExportingPDF` flips to true (and again before the temp-file
    /// write), so SwiftUI gets a chance to actually paint the "Preparing
    /// PDF…" button state between those points instead of the whole
    /// synchronous render+write hiding it entirely. The render itself still
    /// runs on the main actor — one beat of latency, not a full off-main fix.
    /// Renders the verified AI report and attaches it to the already-saved
    /// `MedicalReport` as a `ReportAttachment` (so it shows up in the
    /// Documents library) — but only the FIRST time either "Share PDF" or
    /// "Open" is pressed. Both actions call this; caching the result in
    /// `renderedPDFData` is what keeps a second tap (e.g. sharing, then also
    /// opening) from calling `AIReportPDFExporter.render` again and
    /// attaching a second, duplicate PDF to the report.
    private func renderAndAttachPDFIfNeeded() -> Data? {
        if let renderedPDFData { return renderedPDFData }
        guard case .aiReport(let report) = stage, let savedReport else { return nil }

        let review = currentReview(including: savedReport)
        let data = AIReportPDFExporter.render(
            report: report,
            review: review,
            scannedLabs: savedReport.labResults,
            profileName: fetchProfile()?.name ?? "",
            generatedAt: Date.now
        )
        guard !data.isEmpty else { return nil }

        let filename = "AI Analysis — \(Date.now.formatted(date: .abbreviated, time: .omitted)).pdf"
        savedReport.attachments.append(ReportAttachment(filename: filename, kind: .pdf, data: data))
        renderedPDFData = data
        return data
    }

    /// "Share PDF": renders (or reuses) the PDF via
    /// `renderAndAttachPDFIfNeeded()` and opens the system share sheet with
    /// the file. The attachment is kept even if the user cancels or the
    /// share sheet itself can't be prepared — only rendering can fail this
    /// early, and that's surfaced inline via `pdfExportError`.
    ///
    /// `AIReportPDFExporter.render` takes SwiftData model objects directly
    /// (`scannedLabs: [LabResult]`, and `HealthReview` is built from model
    /// data too) — SwiftData models aren't `Sendable` and stay pinned to
    /// this context's actor (main), so genuinely moving the render off-main
    /// would require the exporter's API to accept `Sendable` value-type
    /// snapshots instead, which is a larger change than this fix covers.
    /// The minimal, actor-safe improvement taken here: do the work inside a
    /// `Task { @MainActor in ... }` with an `await Task.yield()` right after
    /// `isExportingPDF` flips to true (and again before the temp-file
    /// write), so SwiftUI gets a chance to actually paint the "Preparing…"
    /// button state between those points instead of the whole synchronous
    /// render+write hiding it entirely. The render itself still runs on the
    /// main actor — one beat of latency, not a full off-main fix.
    private func shareAIReportPDF() {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        pdfExportError = nil

        Task { @MainActor in
            await Task.yield()

            guard let data = renderAndAttachPDFIfNeeded() else {
                pdfExportError = "Couldn't create the PDF. Please try again."
                isExportingPDF = false
                return
            }

            let filename = "AI Analysis — \(Date.now.formatted(date: .abbreviated, time: .omitted)).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            await Task.yield()
            do {
                try data.write(to: tempURL, options: .atomic)
                shareItem = ShareItem(url: tempURL)
            } catch {
                pdfExportError = "The PDF was saved to the report, but couldn't be prepared for sharing."
            }
            isExportingPDF = false
        }
    }

    /// "Open": renders (or reuses) the PDF via `renderAndAttachPDFIfNeeded()`
    /// and previews it in-app with the same `PDFKitView` used for a saved
    /// attachment's own viewer (`AttachmentViewer` in `ReportDetailView.swift`),
    /// instead of round-tripping through the system share sheet just to look
    /// at it.
    private func openAIReportPDF() {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        pdfExportError = nil

        Task { @MainActor in
            await Task.yield()
            guard renderAndAttachPDFIfNeeded() != nil else {
                pdfExportError = "Couldn't create the PDF. Please try again."
                isExportingPDF = false
                return
            }
            showingPDFPreview = true
            isExportingPDF = false
        }
    }
}

/// Axis bounds for a `RangeBar` built around a reference range: padded on
/// both sides so the out-of-range zones read clearly, and widened further
/// whenever the value itself sits outside that padding so the marker is
/// never clipped to the bar's edge. `private` and intentionally duplicated
/// per file (see the identical helper in `ScannedResultsSheet.swift`) rather
/// than lifted into `Support/EditorialComponents.swift`, which this agent
/// doesn't own.
private func rangeBarAxis(range: ClosedRange<Double>, value: Double) -> (min: Double, max: Double) {
    let width = range.upperBound - range.lowerBound
    let pad = width > 0 ? width * 0.35 : max(abs(range.upperBound), 1) * 0.2
    let lower = Swift.min(range.lowerBound - pad, value - pad * 0.15)
    let upper = Swift.max(range.upperBound + pad, value + pad * 0.15)
    return (lower, upper)
}

// MARK: - Header

private struct ScanReportHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            Text("Scan a Report")
                .font(.title2.bold())
            Text("Photograph or import a document — Gemocode reads the lab values for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Action card

/// One scan action, styled as an inset-card row (leading ink icon, title +
/// subtitle, trailing chevron) rather than a floating glass card — the
/// editorial system's "one featured block" treatment, used here for the two
/// top-level scan entry points.
private struct ScanActionCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Editorial.muted(colorScheme))
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let category: ReportCategory
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label(category.displayName, systemImage: category.systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Editorial.canvas(colorScheme) : Editorial.muted(colorScheme))
                .background(
                    Capsule().fill(isSelected ? Editorial.ink(colorScheme) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Editorial.controlBorder(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Camera capture

/// Thin `UIImagePickerController` wrapper for capturing a single photo of a
/// document. `ScanReportView.presentCamera()` gates presentation on camera
/// availability and (once configured) permission, so this view only ever
/// appears when it's safe to.
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        /// JPEG encoding (`jpegData`) and downsampling (`ImageDownsampler`)
        /// are both pure, read-only work over an already-captured `UIImage`
        /// — safe to run off the main actor — so this hops to
        /// `Task.detached` for that work instead of blocking the delegate
        /// callback (which runs on main) with a full-resolution encode.
        /// `onCapture`/`dismiss` are captured as locals rather than via
        /// `self` so the detached closure doesn't need to touch the
        /// (non-`Sendable`) `Coordinator` instance at all. Behavior is
        /// unchanged: a nil image still just dismisses, and a decode/encode
        /// failure still skips `onCapture` — only where the encode runs has
        /// moved.
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                dismiss()
                return
            }
            let onCapture = onCapture
            let dismiss = dismiss
            Task.detached {
                let data = image.jpegData(compressionQuality: 0.9)
                    .map { jpeg in ImageDownsampler.downsampledJPEG(from: jpeg) ?? jpeg }
                await MainActor.run {
                    if let data {
                        onCapture(data)
                    }
                    dismiss()
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Share sheet

/// Thin `UIActivityViewController` wrapper for sharing the exported AI
/// report PDF. Presented via `.sheet(item:)` rather than `ShareLink` so the
/// PDF can be attached to the saved report *before* the share UI appears,
/// regardless of whether the user completes or cancels the share.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
