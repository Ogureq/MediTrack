import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

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
    @ObservedObject private var premiumStore = PremiumStore.shared

    // Queried so the post-save AI stage can build a `HealthReview` over the
    // freshly saved data exactly as `ReviewScreen` does — this view has no
    // other way to see the rest of the user's records.
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]

    @State private var attachments: [AttachmentDraft] = []
    @State private var confirmedLabs: [ScannedLabValue] = []
    @State private var scannedValues: [ScannedLabValue] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var showingScanResults = false

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
    /// The report `save()` just inserted — kept so the AI stage can attach
    /// the exported PDF to it and read back its saved lab results.
    @State private var savedReport: MedicalReport?
    @State private var isPulsingAIGenerating = false
    @State private var isExportingPDF = false
    @State private var pdfExportError: String?
    @State private var shareItem: ShareItem?

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
                    confirmedLabs.append(contentsOf: selected)
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
                    ZStack {
                        unlockedBody
                            .disabled(true)
                            .opacity(0.28)
                            .accessibilityHidden(true)
                        lockedCard
                    }
                } else {
                    unlockedBody
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
            }

            if !attachments.isEmpty {
                attachmentsSection
            }

            if !confirmedLabs.isEmpty {
                confirmedLabsSection
            }

            if !scannedValues.isEmpty {
                reviewButton
            }

            if nothingExtracted {
                categoryFallbackSection
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

    private var confirmedLabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Detected Lab Values", systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))
            ForEach(confirmedLabs) { scanned in
                HStack {
                    Text(scanned.reference.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(scanned.value.compactFormatted) \(scanned.reference.unit)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var reviewButton: some View {
        Button {
            showingScanResults = true
        } label: {
            Label(
                "Review \(scannedValues.count) Detected Value\(scannedValues.count == 1 ? "" : "s")",
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
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Glass.accentGradient, in: Circle())
                .accessibilityHidden(true)
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
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text("AI Health Analyst")
                .font(.title2.bold())
            Text("Your scan was saved — here's an AI-assisted read of what it means.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)

        switch stage {
        case .scanning:
            EmptyView()
        case .aiGenerating:
            aiGeneratingCard
        case .aiReport(let report):
            Group {
                aiReportCard(report)
                aiActionButtons
            }
        case .aiFailed(let message):
            Group {
                aiErrorCard(message)
                doneButton
            }
        }
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

    /// Mirrors `ReviewScreen.aiReportContent`'s visual language — overview,
    /// each section, doctor questions, and the same footer — for a verified
    /// `AIHealthReport` rendered inline right after a scan.
    private func aiReportCard(_ report: AIHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Health Analyst", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Glass.accentGradient)

            Text(report.overview)
                .font(.subheadline)

            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if !report.doctorQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Questions for Your Doctor")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(report.doctorQuestions.enumerated()), id: \.offset) { _, question in
                        Label(question, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
            }

            Text("Generated by Claude — informational only, not medical advice.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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

    private var aiActionButtons: some View {
        VStack(spacing: 10) {
            Button {
                exportAIReportPDF()
            } label: {
                Label(isExportingPDF ? "Preparing PDF…" : "Save as PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(isExportingPDF)
            .accessibilityHint("Creates a PDF of this AI report, attaches it to the saved report, and opens the share sheet.")

            if let pdfExportError {
                Text(pdfExportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            doneButton
        }
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
            if let data = try? await item.loadTransferable(type: Data.self) {
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
        } else {
            scanAttachments()
        }
    }

    /// Runs `LabScanService` over every current attachment — the same
    /// scan machinery `EditReportView` exposes behind a button, just kicked
    /// off automatically the moment a document is attached. Values already
    /// confirmed are filtered out so re-scanning after a new attachment
    /// only surfaces what's new.
    private func scanAttachments() {
        guard !attachments.isEmpty else { return }
        isScanning = true
        let inputs = attachments.map { (kind: $0.kind, data: $0.data) }
        let existingKeys = Set(confirmedLabs.map { $0.reference.id.lowercased() })
        Task {
            let found = await LabScanService.scan(attachments: inputs)
                .filter { !existingKeys.contains($0.reference.id.lowercased()) }
            scannedValues = found
            isScanning = false
            hasScanned = true
            if !found.isEmpty {
                showingScanResults = true
            }
        }
    }

    // MARK: - Camera permission

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlertMessage = "This device doesn't have a camera available. Use Import PDF or Photo instead."
            showingCameraAlert = true
            return
        }
        // This build doesn't yet declare NSCameraUsageDescription in
        // Info.plist — presenting the camera without it would crash at the
        // OS level. Fail soft to the alert instead until that key is added.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            cameraAlertMessage = "Camera access isn't configured in this build yet. Use Import PDF or Photo instead."
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
                        cameraAlertMessage = "Camera access was denied. Enable it in Settings, or use Import PDF or Photo instead."
                        showingCameraAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = "Camera access is disabled for Gemocode. Enable it in Settings, or use Import PDF or Photo instead."
            showingCameraAlert = true
        @unknown default:
            cameraAlertMessage = "Camera access isn't available. Use Import PDF or Photo instead."
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

        for scanned in confirmedLabs {
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

    /// Nudges the user to re-test in ~90 days after they log a new report
    /// that includes at least one lab result. Neutral, non-urgent copy — a
    /// wellness nudge, not medical advice. Replaces any previously
    /// scheduled nudge so only the most recent lab report restarts the
    /// countdown.
    private func scheduleRetestNudge() {
        NotificationService.cancelReminder(id: Self.retestNudgeID)
        let fireDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now.addingTimeInterval(90 * 86_400)
        Task {
            if await NotificationService.requestAuthorization() {
                NotificationService.scheduleOneTime(
                    id: Self.retestNudgeID,
                    title: "Time for a Follow-Up?",
                    body: "It's been 3 months since your last lab report — re-test to see your trend.",
                    at: fireDate
                )
            }
        }
    }

    // MARK: - AI report generation

    /// A short, caller-built profile description ("42-year-old male;
    /// conditions: hypertension"). Identical to `ReviewScreen.aiProfileSummary`
    /// — duplicated rather than shared, per this file's edit-ownership: this
    /// view has no shared AI-helper module of its own to put it in.
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

    /// `AnalysisEngine.generateReview` over every queried record, patched to
    /// guarantee `savedReport` is included even on the very first call right
    /// after `save()` inserts it — this view's `@Query` results may not have
    /// refreshed yet at that point.
    private func currentReview(including savedReport: MedicalReport) -> HealthReview {
        var allReports = reports
        if !allReports.contains(where: { $0.persistentModelID == savedReport.persistentModelID }) {
            allReports.append(savedReport)
        }
        return AnalysisEngine.generateReview(
            profile: profiles.first,
            reports: allReports,
            vitals: vitals,
            medications: medications,
            symptoms: symptoms,
            appointments: appointments
        )
    }

    /// Runs the same `AnalysisEngine.generateReview` → `AISummaryService.generateReport`
    /// pipeline `ReviewScreen` uses, over the just-saved report plus every
    /// other queried record. Never blocks or loses the scan: the report was
    /// already saved before this is called, and any failure or refusal here
    /// just shows a friendly inline error next to the `Done` button.
    private func generateAIReport(for report: MedicalReport) {
        stage = .aiGenerating
        let review = currentReview(including: report)
        let profileSummary = aiProfileSummary

        Task {
            do {
                let generated = try await AISummaryService.generateReport(
                    review: review,
                    profileSummary: profileSummary,
                    deltas: []
                )
                Haptics.success()
                stage = .aiReport(generated)
                await onAIReportGenerated()
            } catch {
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
    private func exportAIReportPDF() {
        guard case .aiReport(let report) = stage, let savedReport, !isExportingPDF else { return }
        isExportingPDF = true
        pdfExportError = nil

        let review = currentReview(including: savedReport)
        let now = Date.now
        let data = AIReportPDFExporter.render(
            report: report,
            review: review,
            scannedLabs: savedReport.labResults,
            profileName: profiles.first?.name ?? "",
            generatedAt: now
        )

        guard !data.isEmpty else {
            pdfExportError = "Couldn't create the PDF. Please try again."
            isExportingPDF = false
            return
        }

        let filename = "AI Analysis — \(now.formatted(date: .abbreviated, time: .omitted)).pdf"
        savedReport.attachments.append(ReportAttachment(filename: filename, kind: .pdf, data: data))

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL, options: .atomic)
            shareItem = ShareItem(url: tempURL)
        } catch {
            pdfExportError = "The PDF was saved to the report, but couldn't be prepared for sharing."
        }
        isExportingPDF = false
    }
}

// MARK: - Header

private struct ScanReportHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

private struct ScanActionCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let category: ReportCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(category.displayName, systemImage: category.systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Glass.accentGradient) : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(Capsule().strokeBorder(Glass.bevelStroke, lineWidth: 1))
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

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }
            dismiss()
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
