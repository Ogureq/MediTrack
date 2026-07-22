import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit
import PDFKit

/// Single-flag gate for the AI-reading paths — the AI scan engine and the
/// auto-generated AI report after save. Flip `reportCreation` to `false` to
/// make AI reading unconditionally available — that one-line edit is the
/// entire revert of the premium gate placed around AI. Report *creation*
/// itself (photographing/importing a document, on-device OCR, and saving)
/// is never gated by this flag, and never was meant to be: it's a local
/// feature and stays free and unmetered regardless of premium/quota state.
enum PremiumGates {
    static let reportCreation = true
}

/// Scan-first report creation: photograph or import a document, then choose
/// how it gets read — AI (reads almost any report, one free lifetime scan,
/// then Premium) or fully on-device (`LabScanService`'s Vision OCR, free
/// and unmetered, always). Confirm the recognized values, save. There is no
/// manual entry form here by design — the manual form still exists for
/// *editing* an existing report (`EditReportView`), which is how users fix
/// or fill in anything a scan missed.
///
/// AI availability (both the AI engine choice and the post-save auto
/// report) is gated by `PremiumGates.reportCreation` + `isAIScanLocked`:
/// premium or a remaining free credit unlocks it, and once that credit is
/// spent the AI option steps aside for a non-blocking upsell card
/// (`lockedCard`) while the rest of the screen — on-device scanning,
/// saving — stays exactly as usable as it always was. Exactly one free AI
/// credit is spent per flow no matter how many AI actions that flow uses —
/// see `aiCreditConsumedThisFlow`.
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

    // MARK: - AI vs. on-device scan choice

    /// Presented after new camera/photo attachments arrive and before any
    /// reading runs — one custom bottom sheet used for both a single new
    /// photo and a multi-photo batch alike (see `promptEngineChoiceIfNeeded`
    /// and `ScanEngineChoiceSheet` below). Replaces the old system
    /// `.confirmationDialog` entirely — the owner called it "cheap"; a
    /// custom sheet lets both options show a real icon, title, and one-line
    /// caption instead of a dialog's plain button titles.
    @State private var showingEngineChoiceSheet = false

    /// IDs of `scannedValues`/`confirmedLabs` entries that came from
    /// `AIScanService` rather than `LabScanService` — `ScannedLabValue`
    /// doesn't carry its own provenance (that struct lives in
    /// `LabScanService.swift`, which this pass doesn't touch), so this is
    /// tracked alongside it here, keyed by the value's own stable `id`.
    /// Read by `save()` to decide whether this save spends the free AI
    /// credit (see `aiCreditConsumedThisFlow`).
    @State private var aiSourcedValueIDs: Set<UUID> = []

    /// Facility/clinic name the AI scan found printed on the report (see
    /// `AIScanService.AIScanResult.facility`) — `nil` until an AI-scanned
    /// image actually reports one, and never populated by the on-device OCR
    /// path (`LabScanService` has no notion of a facility field). Drives
    /// `clinicAppointmentCard` in the post-save stage. First non-empty value
    /// wins across a multi-image batch — a later page of the same report
    /// shouldn't override an earlier, likely-letterhead page's answer.
    @State private var scannedFacility: String?

    /// Set at most once per flow — the moment either an AI-extraction save
    /// or a successful AI report generation actually completes — so a scan
    /// that uses AI in more than one way (e.g. AI-extracts, saves, then the
    /// auto-run report also succeeds) only ever spends ONE free credit.
    /// Never set for a scan that only used the on-device path, and never
    /// set just because AI extraction *ran* — only on a completed save or a
    /// report the user actually saw, matching the existing
    /// cancel-on-`.onDisappear` semantics for the AI report stage.
    @State private var aiCreditConsumedThisFlow = false

    @State private var showingAIScanErrorAlert = false
    @State private var aiScanErrorMessage = ""
    /// One-shot "AI wasn't available, so Gemocode used the on-device scan
    /// instead" banner — set when `AIScanService.extract` throws
    /// `.notConfigured`. Left on for the rest of this flow rather than
    /// auto-dismissed; there's no ongoing timer to drive that, and it's a
    /// harmless, low-noise reminder either way.
    @State private var showingAINotConfiguredNotice = false

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
    /// The `Medication`s `save()`'s automatic `ActionPlan` pass created for
    /// THIS flow (via `SupplementPlanApplier.apply`) — empty until a save
    /// actually yields plan items. Drives `supplementAddedBanner` (shown
    /// whenever non-empty) and is exactly what `undoAutoSupplements()`
    /// unwinds. Owner decision: this runs automatically, never as a choice —
    /// see `applyAutoSupplements(for:)`.
    @State private var autoAddedSupplements: [Medication] = []
    /// User dismissed `clinicAppointmentCard` without adding the
    /// appointment — the card never reappears for the rest of this flow.
    @State private var dismissedClinicAppointmentCard = false
    /// Set once `addClinicAppointment()` actually inserts the `Appointment`
    /// — swaps the card to a small confirmation instead of hiding it.
    @State private var clinicAppointmentAdded = false
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

    /// Whether the scan flow is locked: not premium AND the free lifetime
    /// `AIReportQuota` credit is already spent. Gates BOTH scan engines
    /// (owner decision: all scan types are one-free-then-Premium) plus the
    /// post-save auto AI report. The credit itself is only ever consumed
    /// once per flow, when a scan save or AI report actually completes —
    /// see `aiCreditConsumedThisFlow` — never merely by checking this.
    private var isAIScanLocked: Bool {
        PremiumGates.reportCreation
            && !premiumStore.isPremium
            && AIReportQuota.remaining(defaults: .standard) == 0
    }

    /// Saving is part of the metered scan flow: locked once the free scan
    /// credit is spent without Premium — unless the credit was consumed in
    /// THIS flow, which keeps the current flow's save/report path usable.
    private var canSave: Bool {
        !attachments.isEmpty && !isScanning && (!isAIScanLocked || aiCreditConsumedThisFlow)
    }

    /// True once a scan has run over every current attachment and found
    /// nothing new — the trigger for the category fallback chips and the
    /// "couldn't find lab values" note.
    private var nothingExtracted: Bool {
        hasScanned && !isScanning && confirmedLabs.isEmpty && scannedValues.isEmpty
    }

    /// Display-only rename of `ReportCategory.labReport`'s user-facing
    /// name from "Lab Report" to "Bloodwork". `ReportCategory.displayName`
    /// itself lives in `Models/Models.swift` (owned by a different pass, so
    /// its localized "Lab Report" string — `report.category.labReport` in
    /// `Model.xcstrings` — is left exactly as it is); this is purely a
    /// cosmetic substitute used everywhere THIS file needs to show that
    /// category name to a user. `ReportsListView`/`ReportDetailView` carry
    /// their own identically-named, independently-duplicated copy of this
    /// same idea (per this pass's file-ownership split), since they need it
    /// to rename an already-STORED title rather than build one fresh.
    private var bloodworkCategoryLabel: String {
        String(localized: "Bloodwork")
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
            .navigationTitle(stage.isScanning ? "Scan Bloodwork" : "AI Analysis")
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
                    promptEngineChoiceIfNeeded()
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
            // One custom bottom sheet for every new-photo case — single
            // capture or multi-photo batch alike — replacing the old system
            // `.confirmationDialog` the owner called "cheap". See
            // `ScanEngineChoiceSheet` below.
            .sheet(isPresented: $showingEngineChoiceSheet) {
                ScanEngineChoiceSheet(
                    onChooseAI: { scanAttachmentsWithAI() },
                    onChooseOnDevice: { scanAttachments() }
                )
            }
            .alert("AI Scan Failed", isPresented: $showingAIScanErrorAlert) {
                Button("Try On-Device Instead") { scanAttachments() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(aiScanErrorMessage)
            }
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(activityItems: [item.url]) {
                    shareItem = nil
                }
            }
            .onAppear {
                // SwiftUI also fires `.onDisappear` when another sheet (the
                // camera, the photo picker) covers this one — not only on a
                // real dismissal. Without this reset, that transient
                // disappearance would latch `hasDisappeared` true for the
                // rest of the flow and silently suppress the scan-results
                // sheet from then on.
                hasDisappeared = false
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
                unlockedBody
                    .transaction { $0.animation = nil }
            }
        case .aiGenerating, .aiReport, .aiFailed:
            aiStageBody
        }
    }

    @ViewBuilder
    private var unlockedBody: some View {
        VStack(spacing: 16) {
            if isAIScanLocked {
                lockedCard
                    .transaction { $0.animation = nil }
            } else {
                scanActions
            }

            if showingAINotConfiguredNotice {
                Label(
                    "AI scanning isn't available right now — Gemocode used the on-device scan instead.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

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
                            priorValue: priorValues[entry.scanned.reference.id.lowercased()]
                        )
                    }
                }
            }
            if !inRangeList.isEmpty {
                MicroLabel("In range · \(inRangeList.count)")
                    .padding(.top, outOfRange.isEmpty ? 0 : 16)
                VStack(spacing: 0) {
                    ForEach(visibleInRange, id: \.scanned.id) { entry in
                        confirmedLabRow(entry, compact: true, priorValue: nil)
                    }
                }
                if hiddenInRangeCount > 0 {
                    Button {
                        withAnimation { showAllInRangeValues = true }
                    } label: {
                        Text("Show \(hiddenInRangeCount) more ↗")
                            .font(.system(size: 13))
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
        // Pure display — never stored (see `save()`, which still builds the
        // ACTUAL saved title from `category.displayName`, unchanged, since
        // that string IS persisted). "Bloodwork" here is purely cosmetic:
        // it previews what `ReportsListView`/`ReportDetailView` will show
        // once saved, since those apply the identical rename at their own
        // display time — see `bloodworkDisplayTitle` in those files.
        let title = "\(bloodworkCategoryLabel) — \(Date.now.formatted(date: .abbreviated, time: .omitted))"
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
                    .font(.system(size: 13))
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

    /// A single confirmed-value row. The full (`compact: false`) form shows
    /// name + value + tag on one line and the range bar beneath it — used
    /// for out-of-range values. The compact form drops the tag (the section
    /// header already says "In Range") and shows a slimmer inline bar next
    /// to the value, matching the quieter in-range ledger in the mockups.
    /// `priorValue` only ever feeds the full form's caption line — the
    /// compact in-range rows never pass it.
    @ViewBuilder
    private func confirmedLabRow(
        _ entry: (scanned: ScannedLabValue, status: LabStatus, range: ClosedRange<Double>?),
        compact: Bool,
        priorValue: Double?
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
                    if let caption = scannedRowCaption(range: range, priorValue: priorValue, currentValue: entry.scanned.value) {
                        Text(caption)
                            .font(.system(size: 13))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
            }
            .ledgerRow()
        }
    }

    /// Builds the "lab range %@–%@ · ↗ up from %@" caption for one
    /// out-of-range confirmed row — range plus, only when there's an actual
    /// prior saved value for this series, a trend arrow. No longer mentions
    /// a supplement suggestion: supplements now auto-add on save (see
    /// `applyAutoSupplements(for:)`), so there's nothing left to "suggest"
    /// here.
    private func scannedRowCaption(
        range: ClosedRange<Double>,
        priorValue: Double?,
        currentValue: Double
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

    /// Blocking upsell card, shown IN PLACE of the scan actions once the
    /// free scan credit is spent without Premium — both engines are
    /// metered, so there is nothing scannable to offer underneath it.
    private var lockedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            MicroLabel("Premium")
            Text("Unlock Unlimited Scans")
                .font(.headline)
            Text("You've used your free scan — Premium unlocks unlimited.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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
        .accessibilityLabel("Unlock unlimited scans. You've used your free scan — Premium unlocks unlimited.")
        .accessibilityHint("Double tap Unlock Premium to see plans.")
    }

    // MARK: - AI Analysis stage

    @ViewBuilder
    private var aiStageBody: some View {
        // The auto-add banner coexists with whichever AI-report sub-stage is
        // showing (generating/succeeded/failed) — it's about what `save()`
        // already did, independent of whether the AI report itself succeeds.
        if !autoAddedSupplements.isEmpty {
            supplementAddedBanner
        }
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
            clinicAppointmentCard
            if !premiumStore.isPremium {
                Text("Your first report is free — this one used your lifetime trial.")
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        case .aiFailed(let message):
            aiGeneratingHeader
            aiErrorCard(message)
            clinicAppointmentCard
            doneButton
        }
    }

    // MARK: - Auto-added supplements banner

    /// "Added N supplements + reminders · Undo" — shown whenever `save()`'s
    /// automatic `ActionPlan` pass (`applyAutoSupplements(for:)`) actually
    /// created at least one `Medication` for this flow. The disclaimer for
    /// what a supplement suggestion means lives on the Supplements page
    /// itself (`ActionPlan.disclaimer`, via `SupplementsView`), not
    /// duplicated here.
    private var supplementAddedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "pills.fill")
                .font(.system(size: 13))
                .foregroundStyle(Editorial.tagGood(colorScheme))
                .accessibilityHidden(true)
            Text(autoAddedSupplements.count == 1
                ? String(localized: "Added 1 supplement + reminder")
                : String(localized: "Added \(autoAddedSupplements.count) supplements + reminders"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Editorial.ink(colorScheme))
            Spacer(minLength: 8)
            Button {
                undoAutoSupplements()
            } label: {
                Text("Undo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Editorial.accent(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Undoes exactly what `applyAutoSupplements(for:)` created THIS flow —
    /// deletes those `Medication`s and cancels their reminders via
    /// `SupplementPlanApplier.unapply`, then clears the local list so the
    /// banner disappears (it's only ever shown while the list is non-empty).
    private func undoAutoSupplements() {
        guard !autoAddedSupplements.isEmpty else { return }
        SupplementPlanApplier.unapply(autoAddedSupplements, context: modelContext)
        autoAddedSupplements = []
        Haptics.success()
    }

    // MARK: - Clinic -> appointment card

    /// A next retest date derived from the labs THIS save confirmed —
    /// mirrors `scheduleRetestNudge()`'s "shortest known interval wins"
    /// logic, but never falls back to the generic 90-day wellness nudge:
    /// `clinicAppointmentCard` only ever offers a date backed by a real
    /// `RetestSchedule` cadence for one of this report's own tests.
    private func nextRetestDate() -> Date? {
        let months = confirmedLabs.compactMap { RetestSchedule.intervalMonths(for: $0.reference.id) }
        guard let shortest = months.min() else { return nil }
        return Calendar.current.date(byAdding: .month, value: shortest, to: .now)
    }

    /// "Next draw at <facility>?" — shown only when the AI scan actually
    /// found a facility name on the report AND there's a concrete next
    /// retest date to offer. Ask-first, never auto-creates: the card just
    /// sits there until tapped, and can be dismissed instead with no
    /// appointment ever created.
    @ViewBuilder
    private var clinicAppointmentCard: some View {
        if let facility = scannedFacility, !facility.isEmpty,
           let retestDate = nextRetestDate(),
           !dismissedClinicAppointmentCard {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    if clinicAppointmentAdded {
                        Label("Appointment added", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Editorial.tagGood(colorScheme))
                    } else {
                        Text("Next draw at \(facility)?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        Button {
                            addClinicAppointment(facility: facility, retestDate: retestDate)
                        } label: {
                            Text("Add Appointment")
                        }
                        .buttonStyle(AccentPillButtonStyle())
                    }
                }
                Spacer(minLength: 8)
                if !clinicAppointmentAdded {
                    Button {
                        dismissedClinicAppointmentCard = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dismiss"))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// Creates the follow-up-draw `Appointment` — existing model init
    /// conventions (mirrors `AppointmentsView.save()`'s own construction and
    /// day-before reminder scheduling): `location`/`notes` = the scanned
    /// facility name, `date` = the next retest date at 8:30 AM, reminder on.
    private func addClinicAppointment(facility: String, retestDate: Date) {
        let apptDate = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: retestDate) ?? retestDate
        let appointment = Appointment(
            title: String(localized: "Follow-Up Blood Draw"),
            location: facility,
            date: apptDate,
            notes: facility,
            reminderEnabled: true
        )
        modelContext.insert(appointment)

        if apptDate > .now {
            let id = appointment.reminderID
            // Reuses the "at %@" fragment `AppointmentsView.save()` already
            // uses for its own day-before reminder body (there, %@ is a
            // time; here it's the facility name) rather than inventing a
            // new composite key for the same "title + where" shape.
            let body = [
                appointment.title,
                String(format: String(localized: "at %@"), facility),
            ].joined(separator: " ")
            let fireDate = apptDate.addingTimeInterval(-86_400)
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleOneTime(
                        id: id,
                        title: String(localized: "Appointment Tomorrow"),
                        body: body,
                        at: fireDate
                    )
                }
            }
        }

        Haptics.success()
        clinicAppointmentAdded = true
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
                    .font(.system(size: 13))
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
                .font(.system(size: 13))
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
        if addedAny { promptEngineChoiceIfNeeded() }
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
        // PDFs skip the engine choice (AI extraction takes images only)
        // but not the meter: no free-ride scan for locked flows.
        if addedAny, !isAIScanLocked || aiCreditConsumedThisFlow { scanAttachments() }
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
            // Mid-flow rescan of an already-authorized flow — permitted
            // when the flow consumed its credit even though the global
            // meter now reads locked.
            if !isAIScanLocked || aiCreditConsumedThisFlow {
                scanAttachments()
            }
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
            // See the AI path's matching `defer`: the re-entrancy latch must
            // clear even when cancelled, or the scan button dies for the
            // rest of this sheet's life.
            defer { isScanning = false }
            let found = await LabScanService.scan(attachments: inputs)
                .filter { !existingKeys.contains($0.reference.id.lowercased()) }
            // Cancelled (sheet dismissed mid-OCR, see .onDisappear below) —
            // skip every mutation, including `hasScanned`, rather than
            // update state on a view that's gone.
            guard !Task.isCancelled else { return }
            scannedValues.append(contentsOf: found)
            scannedAttachmentIDs.formUnion(newlyScannedIDs)
            hasScanned = true
            // Belt-and-suspenders on top of the cancellation guard above:
            // never present a sheet once the view has already torn down.
            if !found.isEmpty && !hasDisappeared {
                showingScanResults = true
            }
        }
    }

    /// After new camera/photo attachments arrive (never PDFs — those go
    /// straight to `scanAttachments()` via `handleFileImport`, since
    /// `AIScanService.extract` only takes a `UIImage`), lets the user pick
    /// the reading engine before anything runs — the same custom sheet for
    /// a single new photo or a multi-photo batch alike. Does nothing while
    /// the scan flow is locked (`isAIScanLocked`) — both engines are
    /// metered, and `lockedCard` explains why over in `unlockedBody`.
    private func promptEngineChoiceIfNeeded() {
        // Owner decision: ALL scan types share the one-free-then-Premium
        // gate. When the credit is spent and there's no subscription,
        // neither engine runs — `lockedCard` (shown in place of the scan
        // actions) explains and routes to the paywall.
        guard !isAIScanLocked else { return }
        let pendingCount = attachments.filter { !scannedAttachmentIDs.contains($0.id) }.count
        guard pendingCount > 0 else { return }
        showingEngineChoiceSheet = true
    }

    /// AI-first counterpart to `scanAttachments()` above — identical
    /// re-entrancy guard, identical delta-only "unscanned" set keyed by
    /// `scannedAttachmentIDs`, identical existing-key dedupe against
    /// already-scanned/confirmed values, identical cancellation/
    /// `hasDisappeared` belt-and-suspenders. Differs only in HOW each new
    /// attachment is read: one `AIScanService.extract(from:)` call per
    /// image instead of `LabScanService.scan(attachments:)`'s on-device
    /// Vision OCR.
    ///
    /// `AIScanError.notConfigured` is service-wide (missing key/relay), not
    /// per-image, so the loop stops at the first one and routes the WHOLE
    /// batch to the on-device path instead (see `showingAINotConfiguredNotice`)
    /// — none of `unscanned` is marked into `scannedAttachmentIDs` in that
    /// case, so `scanAttachments()` still sees all of them as unscanned.
    /// Any other per-image failure (refused/malformed/transport) surfaces
    /// `showingAIScanErrorAlert` once for the whole batch, and — unlike the
    /// `notConfigured` case — that specific attachment IS left unscanned
    /// too, so "Try On-Device Instead" in the alert can still pick it up.
    ///
    /// Never spends the free AI credit itself — see `aiCreditConsumedThisFlow`,
    /// which is only set on a completed save or a report the user actually
    /// saw, not by extraction succeeding.
    private func scanAttachmentsWithAI() {
        guard !isScanning else { return }
        let unscanned = attachments.filter { !scannedAttachmentIDs.contains($0.id) }
        guard !unscanned.isEmpty else { return }
        isScanning = true
        let existingKeys = Set(confirmedLabs.map { $0.reference.id.lowercased() })
            .union(scannedValues.map { $0.reference.id.lowercased() })

        scanTask = Task {
            var found: [ScannedLabValue] = []
            var succeededIDs: Set<UUID> = []
            var hadPerImageFailure = false
            var lastPerImageFailureDetail: String?
            var hitNotConfigured = false
            // First non-empty facility wins across the batch — see
            // `scannedFacility`'s doc comment.
            var facility: String?

            for draft in unscanned {
                guard !Task.isCancelled else { return }
                guard let image = UIImage(data: draft.data) else {
                    // Undecodable bytes would fail an on-device retry for
                    // the same reason — treat as "read, nothing found"
                    // rather than a retryable failure.
                    succeededIDs.insert(draft.id)
                    continue
                }
                do {
                    let result = try await AIScanService.extract(from: image)
                    found.append(contentsOf: result.values)
                    succeededIDs.insert(draft.id)
                    if facility == nil,
                       let candidate = result.facility?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !candidate.isEmpty {
                        facility = candidate
                    }
                } catch AIScanError.notConfigured {
                    hitNotConfigured = true
                    break
                } catch {
                    hadPerImageFailure = true
                    // Keep the underlying cause — a "couldn't read" that's
                    // really a relay 404/500/decode failure must say so, or
                    // it's undiagnosable from the device.
                    lastPerImageFailureDetail = error.localizedDescription
                }
            }

            // Cancelled (sheet dismissed mid-AI-read) — skip every
            // mutation, exactly like `scanAttachments()`'s own guard.
            // `isScanning` itself is cleared by the `defer` above.
            guard !Task.isCancelled else { return }

            if hitNotConfigured {
                showingAINotConfiguredNotice = true
                scanAttachments()
                return
            }

            let deduped = found.filter { !existingKeys.contains($0.reference.id.lowercased()) }
            aiSourcedValueIDs.formUnion(deduped.map(\.id))
            scannedValues.append(contentsOf: deduped)
            scannedAttachmentIDs.formUnion(succeededIDs)
            hasScanned = true
            if let facility {
                scannedFacility = scannedFacility ?? facility
            }

            // Shown whenever at least one image in the batch genuinely
            // failed to read — even if another image in the same batch DID
            // produce values — since the failed one specifically still
            // needs a retry; it was deliberately left out of
            // `scannedAttachmentIDs` above so "Try On-Device Instead" can
            // pick it up.
            if hadPerImageFailure {
                let base = String(localized: "AI couldn't read this photo — try the on-device scan or retake the photo.")
                aiScanErrorMessage = lastPerImageFailureDetail.map { "\(base)\n\n(\($0))" } ?? base
                showingAIScanErrorAlert = true
            }

            if !deduped.isEmpty && !hasDisappeared {
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

        // Metering: the free AI credit is spent the first time an AI
        // action in this flow actually COMPLETES — either this save (when
        // at least one of the values just saved came from the AI-
        // extraction path, tracked in `aiSourcedValueIDs`) or, below, a
        // successful AI report generation. Setting the flag synchronously
        // here — rather than inside the `Task` that does the actual
        // bookkeeping — is what lets the auto-report gate a few lines down
        // see it in time to allow that follow-on report for free within
        // this same flow, instead of racing an unstructured `Task` that
        // hasn't necessarily run yet.
        // Owner decision: BOTH engines are metered — a completed save that
        // imported scanned values consumes the free credit regardless of
        // which engine read them (recordAICreditUse itself no-ops for
        // premium users, matching the original pattern).
        let usedScanThisSave = !dedupedLabs.isEmpty
        if usedScanThisSave && !aiCreditConsumedThisFlow {
            aiCreditConsumedThisFlow = true
            // Deliberately NOT tied to `scanTask`/`aiTask` cancellation:
            // the report above has already been inserted — this is a
            // completed save, not an in-flight AI action — so swiping the
            // sheet away moments later must not undo the metering.
            Task { await recordAICreditUse() }
        }

        // Auto-add supplements — owner decision: automatic, never a choice.
        // Runs whenever this save confirmed lab results, regardless of
        // premium/AI-report availability: the scan flow itself was already
        // authorized (metered above), so this needs no additional gating.
        if !report.labResults.isEmpty {
            applyAutoSupplements(for: report)
        }

        // Auto-run the AI Health Analyst on the just-saved scan whenever a
        // lab value was confirmed and AI is reachable, instead of
        // dismissing — see `generateAIReport(for:)` below. Gated on AI
        // availability for THIS flow: premium, quota remaining, or the
        // credit this save just spent above (never a second charge for the
        // same flow — see `aiCreditConsumedThisFlow`).
        let aiReportAvailable = aiCreditConsumedThisFlow
            || premiumStore.isPremium
            || AIReportQuota.remaining(defaults: .standard) > 0
        if !report.labResults.isEmpty, AISummaryService.isConfigured, aiReportAvailable {
            savedReport = report
            generateAIReport(for: report)
        } else {
            // This flow consumed the credit but can't deliver the report
            // half (AI unconfigured/unreachable) — record the debt so the
            // trial report isn't lost with the credit.
            if aiCreditConsumedThisFlow && !premiumStore.isPremium {
                AIReportQuota.markReportOwed(defaults: .standard)
            }
            dismiss()
        }
    }

    /// Builds the fresh `HealthReview`/`ActionPlan` for the just-saved
    /// report and, when that plan yields items, applies them via
    /// `SupplementPlanApplier.apply` — the same shared helper
    /// `ActionPlanView`'s own button uses — scheduling a daily reminder for
    /// each newly created supplement exactly like that button does. Skips
    /// silently (no plan, or every suggested supplement already exists) by
    /// simply leaving `autoAddedSupplements` empty, which keeps
    /// `supplementAddedBanner` from ever appearing.
    private func applyAutoSupplements(for report: MedicalReport) {
        let review = currentReview(including: report)
        let existingMedications = (try? modelContext.fetch(FetchDescriptor<Medication>())) ?? []
        let plan = ActionPlan.generate(review: review, medications: existingMedications, now: .now)
        guard !plan.items.isEmpty else { return }

        autoAddedSupplements = SupplementPlanApplier.apply(items: plan.items, context: modelContext) { medication in
            let id = medication.reminderID
            let name = medication.name
            let dosage = medication.dosage
            let time = medication.reminderTime ?? .now
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleDailyReminder(id: id, medicationName: name, dosage: dosage, at: time)
                }
            }
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
                // particular, do NOT call `recordAICreditUse()`: the free
                // lifetime AI trial must only be spent when the user
                // actually saw the result, not for a report generated after
                // they'd already swiped the sheet away.
                guard !Task.isCancelled else { return }
                Haptics.success()
                stage = .aiReport(generated)
                // A delivered report settles any owed-report debt (from a
                // prior broken flow or an earlier failed attempt in this
                // one).
                AIReportQuota.clearReportOwed(defaults: .standard)
                // Spend the free credit here too, UNLESS this flow's save()
                // already spent it for the AI-extraction that fed this same
                // report (see `aiCreditConsumedThisFlow`) — one credit
                // covers the whole flow, never two.
                if !aiCreditConsumedThisFlow {
                    aiCreditConsumedThisFlow = true
                    await recordAICreditUse()
                }
            } catch {
                guard !Task.isCancelled else { return }
                stage = .aiFailed(error.localizedDescription)
                // The save already charged this flow's credit but the
                // report half just failed — record the debt so the trial
                // report isn't lost with the credit (cleared on any later
                // successful generation, incl. an in-flow retry).
                if aiCreditConsumedThisFlow && !premiumStore.isPremium {
                    AIReportQuota.markReportOwed(defaults: .standard)
                }
            }
        }
    }

    /// Metering side effect shared by both AI-credit triggers in this file:
    /// a save() that included AI-extracted values, and a successful AI
    /// report generation the user actually saw. Callers are responsible for
    /// the `aiCreditConsumedThisFlow` once-per-flow guard (see both call
    /// sites) — this just does the actual entitlement-then-record work,
    /// mirroring `ReviewScreen`'s identical pattern: entitlements are
    /// resolved first so a paying subscriber whose StoreKit state hasn't
    /// loaded yet never burns the trial.
    private func recordAICreditUse() async {
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

/// The hero: icon, title, and ONE description line — down from three lines
/// of copy (a second AI sentence plus a separate on-device remark) per the
/// owner's "too much explanatory text" note. The AI-vs-on-device choice
/// itself now lives entirely in `ScanEngineChoiceSheet`, so this no longer
/// needs to pitch either engine by name.
private struct ScanReportHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            Text("Scan Bloodwork")
                .font(.title2.bold())
            Text("Photograph any bloodwork — decoded in seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
                    .font(.system(size: 13))
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

// MARK: - Engine choice (custom bottom sheet)

/// The AI-vs-on-device engine choice, for a single new photo or a
/// multi-photo batch alike — one custom bottom sheet replacing the old
/// system `.confirmationDialog` the owner called "cheap". Two large equal
/// cards (icon + title + a single ≤5-word caption each), AI listed first
/// with the accent icon since it's the primary path; the one sentence about
/// the photo being sent for AI reading lives as a single small footnote
/// below both cards instead of inside either option's copy.
private struct ScanEngineChoiceSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onChooseAI: () -> Void
    let onChooseOnDevice: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                engineCard(
                    icon: "sparkles",
                    title: "AI Scan",
                    caption: "Reads any report",
                    isPrimary: true,
                    action: onChooseAI
                )
                engineCard(
                    icon: "lock.shield",
                    title: "On-Device",
                    caption: "Private, offline",
                    isPrimary: false,
                    action: onChooseOnDevice
                )
            }

            Text("Your photo is sent for AI reading, never stored.")
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxWidth: .infinity)
        .background(Editorial.canvas(colorScheme))
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func engineCard(
        icon: String,
        title: LocalizedStringKey,
        caption: LocalizedStringKey,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isPrimary ? Editorial.accent(colorScheme) : Editorial.ink(colorScheme))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isPrimary ? Editorial.accent(colorScheme).opacity(0.5) : Editorial.controlBorder(colorScheme),
                        lineWidth: isPrimary ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // `Text` concatenation (`+`), not string interpolation of one
        // `LocalizedStringKey` into another — interpolating a
        // `LocalizedStringKey` isn't a supported `appendInterpolation`
        // overload, while `Text + Text` is a plain, well-supported SwiftUI
        // operator that keeps both pieces independently localizable.
        .accessibilityLabel(Text(title) + Text(": ") + Text(caption))
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
